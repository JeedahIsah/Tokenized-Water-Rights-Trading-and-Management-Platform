;; Title: Water Rights Token Contract
;; Description: SIP-010 compliant fungible token representing water rights
;; Version: 1.0.0
;; Author: Water Rights Platform Team
;; License: MIT

;; This contract implements a fungible token standard (SIP-010) to represent
;; water rights as tradeable digital assets. Each token represents a unit
;; of water usage rights that can be transferred, traded, and managed.

;; ===== TRAIT IMPLEMENTATION =====

;; Note: In a real deployment, you would implement the SIP-010 trait
;; (impl-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

;; ===== CONSTANTS =====

;; Token metadata
(define-constant token-name "Water Rights Token")
(define-constant token-symbol "WRT")
(define-constant token-decimals u6) ;; 6 decimals for precise water volume representation
(define-constant token-uri "https://water-rights-platform.com/token-metadata.json")

;; Contract owner (deployer)
(define-constant contract-owner tx-sender)

;; Error codes
(define-constant err-unauthorized (err u100))
(define-constant err-insufficient-balance (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-transfer-to-self (err u103))
(define-constant err-insufficient-allowance (err u104))
(define-constant err-invalid-recipient (err u105))
(define-constant err-token-not-transferable (err u106))

;; Maximum supply limit (1 trillion tokens with 6 decimals = 1 million liters)
(define-constant max-supply u1000000000000)

;; ===== DATA STRUCTURES =====

;; Define the fungible token
(define-fungible-token water-rights-token max-supply)

;; Token balances are handled by the fungible token primitive
;; Additional mappings for enhanced functionality

;; Allowances for third-party transfers (ERC-20 style)
(define-map allowances { owner: principal, spender: principal } uint)

;; Authorized minters (typically the registry contract and regulators)
(define-map authorized-minters principal bool)

;; Token transfer restrictions (for compliance purposes)
(define-data-var transfers-enabled bool true)

;; Total supply tracking
(define-data-var total-minted uint u0)

;; ===== PRIVATE FUNCTIONS =====

;; Validates that an amount is greater than zero
(define-private (is-valid-amount (amount uint))
  (> amount u0)
)

;; Checks if transfers are currently enabled
(define-private (are-transfers-enabled)
  (var-get transfers-enabled)
)

;; Checks if a principal is authorized to mint tokens
(define-private (is-authorized-minter (minter principal))
  (default-to false (map-get? authorized-minters minter))
)

;; ===== READ-ONLY FUNCTIONS (SIP-010 REQUIRED) =====

;; Returns the token name
(define-read-only (get-name)
  (ok token-name)
)

;; Returns the token symbol
(define-read-only (get-symbol)
  (ok token-symbol)
)

;; Returns the number of decimals
(define-read-only (get-decimals)
  (ok token-decimals)
)

;; Returns the balance of a specific account
(define-read-only (get-balance (account principal))
  (ok (ft-get-balance water-rights-token account))
)

;; Returns the total supply of tokens
(define-read-only (get-total-supply)
  (ok (ft-get-supply water-rights-token))
)

;; Returns the token URI for metadata
(define-read-only (get-token-uri)
  (ok (some token-uri))
)

;; ===== ADDITIONAL READ-ONLY FUNCTIONS =====

;; Gets the allowance for a spender from an owner
(define-read-only (get-allowance (owner principal) (spender principal))
  (default-to u0 (map-get? allowances { owner: owner, spender: spender }))
)

;; Checks if transfers are currently enabled
(define-read-only (get-transfers-enabled)
  (var-get transfers-enabled)
)

;; Gets the total amount of tokens minted
(define-read-only (get-total-minted)
  (var-get total-minted)
)

;; Checks if a principal is authorized to mint tokens
(define-read-only (is-minter-authorized (minter principal))
  (is-authorized-minter minter)
)

;; ===== PUBLIC FUNCTIONS =====

;; Authorizes a new minter (only contract owner)
(define-public (authorize-minter (minter principal))
  (begin
    ;; Only contract owner can authorize minters
    (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
    
    ;; Add minter to authorized list
    (map-set authorized-minters minter true)
    
    ;; Log the authorization event
    (print {
      event: "minter-authorized",
      minter: minter,
      authorized-by: contract-caller,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Revokes minter authorization (only contract owner)
(define-public (revoke-minter (minter principal))
  (begin
    ;; Only contract owner can revoke minters
    (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
    
    ;; Remove minter from authorized list
    (map-set authorized-minters minter false)
    
    ;; Log the revocation event
    (print {
      event: "minter-revoked",
      minter: minter,
      revoked-by: contract-caller,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Mints new tokens (only authorized minters)
(define-public (mint (amount uint) (recipient principal))
  (begin
    ;; Validate caller is authorized minter
    (asserts! (is-authorized-minter contract-caller) err-unauthorized)
    
    ;; Validate amount
    (asserts! (is-valid-amount amount) err-invalid-amount)
    
    ;; Check supply limit
    (asserts! (<= (+ (ft-get-supply water-rights-token) amount) max-supply) err-invalid-amount)
    
    ;; Mint the tokens
    (try! (ft-mint? water-rights-token amount recipient))
    
    ;; Update total minted counter
    (var-set total-minted (+ (var-get total-minted) amount))
    
    ;; Log the mint event
    (print {
      event: "tokens-minted",
      amount: amount,
      recipient: recipient,
      minted-by: contract-caller,
      new-balance: (ft-get-balance water-rights-token recipient),
      total-supply: (ft-get-supply water-rights-token),
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Burns tokens from caller's balance (only authorized minters)
(define-public (burn (amount uint))
  (begin
    ;; Validate caller is authorized minter
    (asserts! (is-authorized-minter contract-caller) err-unauthorized)
    
    ;; Validate amount
    (asserts! (is-valid-amount amount) err-invalid-amount)
    
    ;; Check sufficient balance
    (asserts! (>= (ft-get-balance water-rights-token contract-caller) amount) err-insufficient-balance)
    
    ;; Burn the tokens
    (try! (ft-burn? water-rights-token amount contract-caller))
    
    ;; Log the burn event
    (print {
      event: "tokens-burned",
      amount: amount,
      burned-by: contract-caller,
      new-balance: (ft-get-balance water-rights-token contract-caller),
      total-supply: (ft-get-supply water-rights-token),
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Standard transfer function (SIP-010 required)
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    ;; Validate transfers are enabled
    (asserts! (are-transfers-enabled) err-token-not-transferable)
    
    ;; Validate caller is sender
    (asserts! (is-eq contract-caller sender) err-unauthorized)
    
    ;; Validate amount
    (asserts! (is-valid-amount amount) err-invalid-amount)
    
    ;; Validate not transferring to self
    (asserts! (not (is-eq sender recipient)) err-transfer-to-self)
    
    ;; Check sufficient balance
    (asserts! (>= (ft-get-balance water-rights-token sender) amount) err-insufficient-balance)
    
    ;; Execute the transfer
    (try! (ft-transfer? water-rights-token amount sender recipient))
    
    ;; Log the transfer event
    (print {
      event: "tokens-transferred",
      amount: amount,
      from: sender,
      to: recipient,
      memo: memo,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Approve function for allowance-based transfers
(define-public (approve (spender principal) (amount uint))
  (begin
    ;; Validate amount (can be zero to revoke allowance)
    (asserts! (>= amount u0) err-invalid-amount)
    
    ;; Set the allowance
    (map-set allowances { owner: contract-caller, spender: spender } amount)
    
    ;; Log the approval event
    (print {
      event: "allowance-set",
      owner: contract-caller,
      spender: spender,
      amount: amount,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Transfer from allowance (for third-party transfers)
(define-public (transfer-from (amount uint) (owner principal) (recipient principal) (memo (optional (buff 34))))
  (let ((current-allowance (get-allowance owner contract-caller)))
    (begin
      ;; Validate transfers are enabled
      (asserts! (are-transfers-enabled) err-token-not-transferable)
      
      ;; Validate amount
      (asserts! (is-valid-amount amount) err-invalid-amount)
      
      ;; Validate not transferring to self
      (asserts! (not (is-eq owner recipient)) err-transfer-to-self)
      
      ;; Check sufficient allowance
      (asserts! (>= current-allowance amount) err-insufficient-allowance)
      
      ;; Check sufficient balance
      (asserts! (>= (ft-get-balance water-rights-token owner) amount) err-insufficient-balance)
      
      ;; Execute the transfer
      (try! (ft-transfer? water-rights-token amount owner recipient))
      
      ;; Update allowance
      (map-set allowances { owner: owner, spender: contract-caller } (- current-allowance amount))
      
      ;; Log the transfer event
      (print {
        event: "tokens-transferred-from",
        amount: amount,
        from: owner,
        to: recipient,
        spender: contract-caller,
        memo: memo,
        remaining-allowance: (- current-allowance amount),
        block-height: stacks-block-height
      })
      
      (ok true)
    )
  )
)

;; Enable or disable transfers (only contract owner)
(define-public (set-transfers-enabled (enabled bool))
  (begin
    ;; Only contract owner can change transfer status
    (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
    
    ;; Update transfer status
    (var-set transfers-enabled enabled)
    
    ;; Log the status change event
    (print {
      event: "transfers-status-changed",
      enabled: enabled,
      changed-by: contract-caller,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)
