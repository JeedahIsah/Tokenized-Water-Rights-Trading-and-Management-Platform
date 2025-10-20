;; Title: Reputation NFT Contract
;; Description: SIP-009 compliant NFT contract for soulbound reputation tokens
;; Version: 1.0.0
;; Author: Water Rights Platform Team
;; License: MIT

;; This contract implements a non-fungible token (NFT) standard (SIP-009) for
;; reputation tokens. These are soulbound tokens (non-transferable) that recognize
;; users with good compliance history and conservation contributions.

;; ===== CONSTANTS =====

;; Contract owner (deployer)
(define-constant contract-owner tx-sender)

;; Error codes
(define-constant err-unauthorized (err u400))
(define-constant err-token-not-found (err u401))
(define-constant err-invalid-token-id (err u402))
(define-constant err-token-not-transferable (err u403))
(define-constant err-already-owns-token (err u404))
(define-constant err-invalid-metadata (err u405))

;; Token metadata
(define-constant token-name "Water Rights Reputation NFT")
(define-constant token-symbol "WRR")
(define-constant token-uri-base "https://water-rights-platform.com/nft/")

;; Reputation tiers
(define-constant tier-bronze u1)
(define-constant tier-silver u2)
(define-constant tier-gold u3)
(define-constant tier-platinum u4)

;; ===== DATA STRUCTURES =====

;; Counter for generating unique token IDs
(define-data-var next-token-id uint u1)

;; Token ownership mapping (token-id -> owner)
(define-map token-owner uint principal)

;; Token metadata mapping (token-id -> metadata)
(define-map token-metadata uint {
  owner: principal,
  tier: uint,
  achievement: (string-ascii 100),
  issued-at: uint,
  compliance-score: uint
})

;; Track tokens owned by each principal (one per principal for soulbound)
(define-map principal-token principal uint)

;; ===== PRIVATE FUNCTIONS =====

;; Validates that a tier is within acceptable range
(define-private (is-valid-tier (tier uint))
  (and (>= tier tier-bronze) (<= tier tier-platinum))
)

;; Checks if a principal already owns a reputation token
(define-private (already-owns-token (principal-addr principal))
  (is-some (map-get? principal-token principal-addr))
)

;; ===== READ-ONLY FUNCTIONS (SIP-009 REQUIRED) =====

;; Returns the last token ID (total supply)
(define-read-only (get-last-token-id)
  (- (var-get next-token-id) u1)
)

;; Returns the token URI for metadata
(define-read-only (get-token-uri (token-id uint))
  (match (map-get? token-metadata token-id)
    metadata (ok (some (concat token-uri-base (int-to-ascii token-id))))
    (err err-token-not-found)
  )
)

;; Returns the owner of a specific token
(define-read-only (get-owner (token-id uint))
  (match (map-get? token-owner token-id)
    owner (ok (some owner))
    (err err-token-not-found)
  )
)

;; ===== ADDITIONAL READ-ONLY FUNCTIONS =====

;; Gets token metadata
(define-read-only (get-token-metadata (token-id uint))
  (map-get? token-metadata token-id)
)

;; Gets the token owned by a principal (if any)
(define-read-only (get-principal-token (principal-addr principal))
  (map-get? principal-token principal-addr)
)

;; Gets token tier
(define-read-only (get-token-tier (token-id uint))
  (match (map-get? token-metadata token-id)
    metadata (ok (get tier metadata))
    (err err-token-not-found)
  )
)

;; Gets token achievement description
(define-read-only (get-token-achievement (token-id uint))
  (match (map-get? token-metadata token-id)
    metadata (ok (get achievement metadata))
    (err err-token-not-found)
  )
)

;; ===== PUBLIC FUNCTIONS =====

;; Mints a new reputation NFT (only contract owner)
(define-public (mint 
  (recipient principal) 
  (tier uint) 
  (achievement (string-ascii 100)) 
  (compliance-score uint))
  (let ((token-id (var-get next-token-id)))
    (begin
      ;; Only contract owner can mint
      (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
      
      ;; Validate tier
      (asserts! (is-valid-tier tier) err-invalid-metadata)
      
      ;; Recipient cannot already own a token (soulbound - one per principal)
      (asserts! (not (already-owns-token recipient)) err-already-owns-token)
      
      ;; Create the token
      (map-set token-owner token-id recipient)
      (map-set token-metadata token-id {
        owner: recipient,
        tier: tier,
        achievement: achievement,
        issued-at: stacks-block-height,
        compliance-score: compliance-score
      })
      (map-set principal-token recipient token-id)
      
      ;; Increment token ID
      (var-set next-token-id (+ token-id u1))
      
      ;; Log the mint event
      (print {
        event: "nft-minted",
        token-id: token-id,
        recipient: recipient,
        tier: tier,
        achievement: achievement,
        compliance-score: compliance-score,
        block-height: stacks-block-height
      })
      
      (ok token-id)
    )
  )
)

;; Burns a reputation NFT (only owner or contract owner)
(define-public (burn (token-id uint))
  (let ((token-owner-val (unwrap! (map-get? token-owner token-id) err-token-not-found)))
    (begin
      ;; Only token owner or contract owner can burn
      (asserts! (or 
        (is-eq contract-caller token-owner-val)
        (is-eq contract-caller contract-owner)
      ) err-unauthorized)
      
      ;; Remove token ownership
      (map-delete token-owner token-id)
      (map-delete token-metadata token-id)
      (map-delete principal-token token-owner-val)
      
      ;; Log the burn event
      (print {
        event: "nft-burned",
        token-id: token-id,
        owner: token-owner-val,
        burned-by: contract-caller,
        block-height: stacks-block-height
      })
      
      (ok true)
    )
  )
)

;; Transfer function (SIP-009 required) - DISABLED for soulbound tokens
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    ;; Soulbound tokens cannot be transferred
    (err err-token-not-transferable)
  )
)

;; Upgrades a token to a higher tier (only contract owner)
(define-public (upgrade-tier (token-id uint) (new-tier uint))
  (let ((metadata (unwrap! (map-get? token-metadata token-id) err-token-not-found)))
    (begin
      ;; Only contract owner can upgrade
      (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
      
      ;; Validate new tier
      (asserts! (is-valid-tier new-tier) err-invalid-metadata)
      
      ;; New tier must be higher than current
      (asserts! (> new-tier (get tier metadata)) err-invalid-metadata)
      
      ;; Update tier
      (map-set token-metadata token-id (merge metadata { tier: new-tier }))
      
      ;; Log the upgrade event
      (print {
        event: "nft-tier-upgraded",
        token-id: token-id,
        owner: (get owner metadata),
        old-tier: (get tier metadata),
        new-tier: new-tier,
        upgraded-by: contract-caller,
        block-height: stacks-block-height
      })
      
      (ok true)
    )
  )
)

