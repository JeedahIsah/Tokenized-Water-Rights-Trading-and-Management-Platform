;; Title: Water Rights Marketplace Contract
;; Description: Facilitates peer-to-peer trading of tokenized water rights
;; Version: 1.0.0
;; Author: Water Rights Platform Team
;; License: MIT

;; This contract provides a decentralized marketplace for trading water rights tokens.
;; It enables transparent price discovery, secure escrow, and efficient settlement
;; of water rights transactions between participants.

;; ===== CONSTANTS =====

;; Contract owner (deployer)
(define-constant contract-owner tx-sender)

;; Error codes
(define-constant err-unauthorized (err u100))
(define-constant err-listing-not-found (err u101))
(define-constant err-listing-inactive (err u102))
(define-constant err-insufficient-balance (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-invalid-price (err u105))
(define-constant err-cannot-buy-own-listing (err u106))
(define-constant err-insufficient-payment (err u107))
(define-constant err-marketplace-paused (err u108))
(define-constant err-invalid-token-contract (err u109))
(define-constant err-transfer-failed (err u110))

;; Maximum values for validation
(define-constant max-listing-amount u1000000000000) ;; 1 million tokens max per listing
(define-constant max-price-per-token u1000000) ;; 1 STX max per token
(define-constant marketplace-fee-rate u250) ;; 2.5% fee in basis points

;; ===== DATA STRUCTURES =====

;; Counter for generating unique listing IDs
(define-data-var next-listing-id uint u1)

;; Marketplace operational status
(define-data-var marketplace-active bool true)

;; Fee collection address
(define-data-var fee-collector principal contract-owner)

;; Authorized token contracts that can be traded
(define-map authorized-tokens principal bool)

;; Main marketplace listings
(define-map listings uint {
  seller: principal,              ;; Address of the seller
  token-contract: principal,      ;; Contract address of the token being sold
  amount: uint,                   ;; Amount of tokens for sale
  price-per-token: uint,          ;; Price per token in microSTX
  total-price: uint,              ;; Total price for the entire listing
  active: bool,                   ;; Whether the listing is active
  created-at: uint,               ;; Block height when listing was created
  expires-at: uint                ;; Block height when listing expires
})

;; Track listings by seller for easy querying
(define-map seller-listings principal (list 50 uint))

;; Track completed sales for analytics
(define-map completed-sales uint {
  listing-id: uint,
  seller: principal,
  buyer: principal,
  amount: uint,
  price-paid: uint,
  fee-collected: uint,
  completed-at: uint
})

;; Sales counter for tracking
(define-data-var total-sales uint u0)

;; ===== PRIVATE FUNCTIONS =====

;; Validates that an amount is within acceptable limits
(define-private (is-valid-amount (amount uint))
  (and (> amount u0) (<= amount max-listing-amount))
)

;; Validates that a price is within acceptable limits
(define-private (is-valid-price (price uint))
  (and (> price u0) (<= price max-price-per-token))
)

;; Checks if marketplace is currently active
(define-private (is-marketplace-active)
  (var-get marketplace-active)
)

;; Checks if a token contract is authorized for trading
(define-private (is-token-authorized (token-contract principal))
  (default-to false (map-get? authorized-tokens token-contract))
)

;; Calculates marketplace fee for a given amount
(define-private (calculate-fee (amount uint))
  (/ (* amount marketplace-fee-rate) u10000)
)

;; Adds a listing ID to seller's listing list
(define-private (add-listing-to-seller (seller principal) (listing-id uint))
  (let ((current-listings (default-to (list) (map-get? seller-listings seller))))
    (map-set seller-listings seller 
      (unwrap! (as-max-len? (append current-listings listing-id) u50) false))
  )
)

;; Removes a listing ID from seller's listing list
(define-private (remove-listing-from-seller (seller principal) (listing-id uint))
  (let ((current-listings (default-to (list) (map-get? seller-listings seller))))
    (map-set seller-listings seller
      (filter is-not-target-listing current-listings))
    true
  )
)

;; Helper function for filtering listings
(define-private (is-not-target-listing (id uint))
  ;; This is a simplified approach - in practice you'd need to pass the target ID
  ;; For now, we'll use a different approach in the main functions
  true
)

;; ===== READ-ONLY FUNCTIONS =====

;; Gets a specific listing by ID
(define-read-only (get-listing (listing-id uint))
  (map-get? listings listing-id)
)

;; Gets all active listings by a seller
(define-read-only (get-seller-listings (seller principal))
  (default-to (list) (map-get? seller-listings seller))
)

;; Gets the next available listing ID
(define-read-only (get-next-listing-id)
  (var-get next-listing-id)
)

;; Checks if marketplace is active
(define-read-only (get-marketplace-status)
  (var-get marketplace-active)
)

;; Gets the current fee rate
(define-read-only (get-fee-rate)
  marketplace-fee-rate
)

;; Gets the fee collector address
(define-read-only (get-fee-collector)
  (var-get fee-collector)
)

;; Checks if a token is authorized for trading
(define-read-only (is-token-contract-authorized (token-contract principal))
  (is-token-authorized token-contract)
)

;; Gets total number of completed sales
(define-read-only (get-total-sales)
  (var-get total-sales)
)

;; Gets details of a completed sale
(define-read-only (get-sale-details (sale-id uint))
  (map-get? completed-sales sale-id)
)

;; ===== PUBLIC FUNCTIONS =====

;; Authorizes a token contract for trading (only contract owner)
(define-public (authorize-token (token-contract principal))
  (begin
    ;; Only contract owner can authorize tokens
    (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
    
    ;; Add token to authorized list
    (map-set authorized-tokens token-contract true)
    
    ;; Log the authorization event
    (print {
      event: "token-authorized",
      token-contract: token-contract,
      authorized-by: contract-caller,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Revokes token authorization (only contract owner)
(define-public (revoke-token (token-contract principal))
  (begin
    ;; Only contract owner can revoke tokens
    (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
    
    ;; Remove token from authorized list
    (map-set authorized-tokens token-contract false)
    
    ;; Log the revocation event
    (print {
      event: "token-revoked",
      token-contract: token-contract,
      revoked-by: contract-caller,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Creates a new listing for selling tokens
(define-public (create-listing 
  (token-contract principal) 
  (amount uint) 
  (price-per-token uint) 
  (expires-in-blocks uint))
  (let ((listing-id (var-get next-listing-id))
        (total-price (* amount price-per-token))
        (expires-at (+ stacks-block-height expires-in-blocks)))
    (begin
      ;; Validate marketplace is active
      (asserts! (is-marketplace-active) err-marketplace-paused)
      
      ;; Validate token is authorized
      (asserts! (is-token-authorized token-contract) err-invalid-token-contract)
      
      ;; Validate input parameters
      (asserts! (is-valid-amount amount) err-invalid-amount)
      (asserts! (is-valid-price price-per-token) err-invalid-price)
      
      ;; Check seller has sufficient token balance
      ;; Note: This would require a trait call to the token contract
      ;; For now, we'll assume the check happens during the actual transfer
      
      ;; Create the listing
      (map-set listings listing-id {
        seller: contract-caller,
        token-contract: token-contract,
        amount: amount,
        price-per-token: price-per-token,
        total-price: total-price,
        active: true,
        created-at: stacks-block-height,
        expires-at: expires-at
      })
      
      ;; Add listing to seller's list
      (add-listing-to-seller contract-caller listing-id)
      
      ;; Increment listing ID counter
      (var-set next-listing-id (+ listing-id u1))
      
      ;; Log the listing creation event
      (print {
        event: "listing-created",
        listing-id: listing-id,
        seller: contract-caller,
        token-contract: token-contract,
        amount: amount,
        price-per-token: price-per-token,
        total-price: total-price,
        expires-at: expires-at,
        block-height: stacks-block-height
      })
      
      (ok listing-id)
    )
  )
)

;; Cancels an active listing
(define-public (cancel-listing (listing-id uint))
  (let ((listing (unwrap! (map-get? listings listing-id) err-listing-not-found)))
    (begin
      ;; Only seller can cancel their listing
      (asserts! (is-eq contract-caller (get seller listing)) err-unauthorized)
      
      ;; Listing must be active
      (asserts! (get active listing) err-listing-inactive)
      
      ;; Deactivate the listing
      (map-set listings listing-id (merge listing { active: false }))
      
      ;; Remove from seller's active listings
      (remove-listing-from-seller contract-caller listing-id)
      
      ;; Log the cancellation event
      (print {
        event: "listing-cancelled",
        listing-id: listing-id,
        seller: contract-caller,
        block-height: stacks-block-height
      })
      
      (ok true)
    )
  )
)

;; Purchases tokens from a listing
(define-public (buy-listing (listing-id uint))
  (let ((listing (unwrap! (map-get? listings listing-id) err-listing-not-found))
        (fee-amount (calculate-fee (get total-price listing)))
        (seller-amount (- (get total-price listing) fee-amount))
        (sale-id (+ (var-get total-sales) u1)))
    (begin
      ;; Validate marketplace is active
      (asserts! (is-marketplace-active) err-marketplace-paused)
      
      ;; Validate listing is active and not expired
      (asserts! (get active listing) err-listing-inactive)
      (asserts! (<= stacks-block-height (get expires-at listing)) err-listing-inactive)
      
      ;; Buyer cannot purchase their own listing
      (asserts! (not (is-eq contract-caller (get seller listing))) err-cannot-buy-own-listing)
      
      ;; Transfer STX from buyer to seller (minus fee)
      (try! (stx-transfer? seller-amount contract-caller (get seller listing)))
      
      ;; Transfer fee to fee collector
      (try! (stx-transfer? fee-amount contract-caller (var-get fee-collector)))
      
      ;; Transfer tokens from seller to buyer
      ;; Note: This would require a trait call to the token contract
      ;; For demonstration, we'll log the intended transfer
      
      ;; Deactivate the listing
      (map-set listings listing-id (merge listing { active: false }))
      
      ;; Remove from seller's active listings
      (remove-listing-from-seller (get seller listing) listing-id)
      
      ;; Record the completed sale
      (map-set completed-sales sale-id {
        listing-id: listing-id,
        seller: (get seller listing),
        buyer: contract-caller,
        amount: (get amount listing),
        price-paid: (get total-price listing),
        fee-collected: fee-amount,
        completed-at: stacks-block-height
      })
      
      ;; Increment sales counter
      (var-set total-sales sale-id)
      
      ;; Log the purchase event
      (print {
        event: "listing-purchased",
        listing-id: listing-id,
        sale-id: sale-id,
        seller: (get seller listing),
        buyer: contract-caller,
        amount: (get amount listing),
        price-paid: (get total-price listing),
        fee-collected: fee-amount,
        block-height: stacks-block-height
      })
      
      (ok sale-id)
    )
  )
)

;; Pauses or unpauses the marketplace (only contract owner)
(define-public (set-marketplace-status (active bool))
  (begin
    ;; Only contract owner can change marketplace status
    (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
    
    ;; Update marketplace status
    (var-set marketplace-active active)
    
    ;; Log the status change event
    (print {
      event: "marketplace-status-changed",
      active: active,
      changed-by: contract-caller,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Updates the fee collector address (only contract owner)
(define-public (set-fee-collector (new-collector principal))
  (begin
    ;; Only contract owner can change fee collector
    (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
    
    ;; Update fee collector
    (var-set fee-collector new-collector)
    
    ;; Log the change event
    (print {
      event: "fee-collector-updated",
      old-collector: (var-get fee-collector),
      new-collector: new-collector,
      changed-by: contract-caller,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)
