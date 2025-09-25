;; Title: Water Rights Registry Contract
;; Description: Maintains an on-chain record of water rights issued by regulators
;; Version: 1.0.0
;; Author: Water Rights Platform Team
;; License: MIT

;; This contract serves as the foundational registry for all legitimate water rights
;; issued by authorized regulators. It provides tamper-proof record keeping and
;; ensures only valid rights can be tokenized and traded.

;; ===== CONSTANTS =====

;; Contract owner (deployer) - typically a regulatory authority
(define-constant contract-owner tx-sender)

;; Error codes for different failure scenarios
(define-constant err-unauthorized (err u100))
(define-constant err-invalid-right-id (err u101))
(define-constant err-right-already-exists (err u102))
(define-constant err-right-not-found (err u103))
(define-constant err-right-expired (err u104))
(define-constant err-right-inactive (err u105))
(define-constant err-invalid-volume (err u106))
(define-constant err-invalid-dates (err u107))
(define-constant err-invalid-region (err u108))

;; Maximum values for validation
(define-constant max-volume u1000000000) ;; 1 billion liters max per right
(define-constant max-region-length u50)
(define-constant max-validity-period u525600) ;; ~1 year in blocks (10 min blocks)

;; ===== DATA STRUCTURES =====

;; Counter for generating unique right IDs
(define-data-var next-right-id uint u1)

;; Registry of authorized regulators who can issue water rights
(define-map authorized-regulators principal bool)

;; Main registry mapping right ID to water right details
(define-map water-rights uint {
  owner: principal,           ;; Current owner of the water right
  volume: uint,              ;; Volume of water in liters
  valid-from: uint,          ;; Block height when right becomes valid
  valid-until: uint,         ;; Block height when right expires
  region: (string-ascii 50), ;; Geographic region identifier
  active: bool,              ;; Whether the right is currently active
  issued-by: principal,      ;; Regulator who issued this right
  issued-at: uint           ;; Block height when right was issued
})

;; Mapping to track rights owned by each principal
(define-map owner-rights principal (list 100 uint))

;; ===== PRIVATE FUNCTIONS =====

;; Validates that a volume amount is within acceptable limits
(define-private (is-valid-volume (volume uint))
  (and (> volume u0) (<= volume max-volume))
)

;; Validates that validity dates are logical (from < until, both in future)
(define-private (are-valid-dates (valid-from uint) (valid-until uint))
  (and 
    (> valid-from stacks-block-height)
    (> valid-until valid-from)
    (<= (- valid-until valid-from) max-validity-period)
  )
)

;; Validates that a region string is properly formatted
(define-private (is-valid-region (region (string-ascii 50)))
  (and 
    (> (len region) u0)
    (<= (len region) max-region-length)
  )
)

;; Checks if a regulator is authorized to issue water rights
(define-private (is-authorized-regulator (regulator principal))
  (default-to false (map-get? authorized-regulators regulator))
)

;; Adds a right ID to an owner's list of rights
(define-private (add-right-to-owner (owner principal) (right-id uint))
  (let ((current-rights (default-to (list) (map-get? owner-rights owner))))
    (map-set owner-rights owner 
      (unwrap! (as-max-len? (append current-rights right-id) u100) false))
  )
)

;; ===== READ-ONLY FUNCTIONS =====

;; Retrieves complete water right information by ID
(define-read-only (get-water-right (right-id uint))
  (map-get? water-rights right-id)
)

;; Gets the current owner of a specific water right
(define-read-only (get-right-owner (right-id uint))
  (match (map-get? water-rights right-id)
    right (some (get owner right))
    none
  )
)

;; Checks if a water right is currently valid (active and not expired)
(define-read-only (is-right-valid (right-id uint))
  (match (map-get? water-rights right-id)
    right (and 
      (get active right)
      (>= stacks-block-height (get valid-from right))
      (<= stacks-block-height (get valid-until right))
    )
    false
  )
)

;; Gets all water right IDs owned by a specific principal
(define-read-only (get-owner-rights (owner principal))
  (default-to (list) (map-get? owner-rights owner))
)

;; Gets the total volume of valid water rights owned by a principal
(define-read-only (get-owner-total-volume (owner principal))
  (let ((right-ids (get-owner-rights owner)))
    (fold calculate-total-volume right-ids u0)
  )
)

;; Helper function for calculating total volume
(define-private (calculate-total-volume (right-id uint) (acc uint))
  (match (map-get? water-rights right-id)
    right (if (is-right-valid right-id)
      (+ acc (get volume right))
      acc
    )
    acc
  )
)

;; Gets the next available right ID
(define-read-only (get-next-right-id)
  (var-get next-right-id)
)

;; Checks if a principal is an authorized regulator
(define-read-only (is-regulator-authorized (regulator principal))
  (is-authorized-regulator regulator)
)

;; ===== PUBLIC FUNCTIONS =====

;; Authorizes a new regulator (only contract owner can do this)
(define-public (authorize-regulator (regulator principal))
  (begin
    ;; Only contract owner can authorize regulators
    (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
    
    ;; Add regulator to authorized list
    (map-set authorized-regulators regulator true)
    
    ;; Log the authorization event
    (print {
      event: "regulator-authorized",
      regulator: regulator,
      authorized-by: contract-caller,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Revokes regulator authorization (only contract owner can do this)
(define-public (revoke-regulator (regulator principal))
  (begin
    ;; Only contract owner can revoke regulators
    (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
    
    ;; Remove regulator from authorized list
    (map-set authorized-regulators regulator false)
    
    ;; Log the revocation event
    (print {
      event: "regulator-revoked",
      regulator: regulator,
      revoked-by: contract-caller,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Issues a new water right (only authorized regulators can do this)
(define-public (issue-water-right 
  (owner principal) 
  (volume uint) 
  (valid-from uint) 
  (valid-until uint) 
  (region (string-ascii 50)))
  (let ((right-id (var-get next-right-id)))
    (begin
      ;; Validate caller is authorized regulator
      (asserts! (is-authorized-regulator contract-caller) err-unauthorized)
      
      ;; Validate input parameters
      (asserts! (is-valid-volume volume) err-invalid-volume)
      (asserts! (are-valid-dates valid-from valid-until) err-invalid-dates)
      (asserts! (is-valid-region region) err-invalid-region)
      
      ;; Create the water right record
      (map-set water-rights right-id {
        owner: owner,
        volume: volume,
        valid-from: valid-from,
        valid-until: valid-until,
        region: region,
        active: true,
        issued-by: contract-caller,
        issued-at: stacks-block-height
      })
      
      ;; Add right to owner's list
      (add-right-to-owner owner right-id)
      
      ;; Increment the right ID counter
      (var-set next-right-id (+ right-id u1))
      
      ;; Log the issuance event
      (print {
        event: "water-right-issued",
        right-id: right-id,
        owner: owner,
        volume: volume,
        region: region,
        valid-from: valid-from,
        valid-until: valid-until,
        issued-by: contract-caller,
        block-height: stacks-block-height
      })
      
      (ok right-id)
    )
  )
)

;; Transfers ownership of a water right
(define-public (transfer-water-right (right-id uint) (new-owner principal))
  (let ((right (unwrap! (map-get? water-rights right-id) err-right-not-found)))
    (begin
      ;; Only current owner can transfer
      (asserts! (is-eq contract-caller (get owner right)) err-unauthorized)
      
      ;; Right must be active and valid
      (asserts! (get active right) err-right-inactive)
      (asserts! (is-right-valid right-id) err-right-expired)
      
      ;; Update the right with new owner
      (map-set water-rights right-id (merge right { owner: new-owner }))
      
      ;; Add right to new owner's list
      (add-right-to-owner new-owner right-id)
      
      ;; Log the transfer event
      (print {
        event: "water-right-transferred",
        right-id: right-id,
        from: (get owner right),
        to: new-owner,
        block-height: stacks-block-height
      })
      
      (ok true)
    )
  )
)

;; Deactivates a water right (only issuing regulator or contract owner)
(define-public (deactivate-water-right (right-id uint))
  (let ((right (unwrap! (map-get? water-rights right-id) err-right-not-found)))
    (begin
      ;; Only issuing regulator or contract owner can deactivate
      (asserts! (or 
        (is-eq contract-caller (get issued-by right))
        (is-eq contract-caller contract-owner)
      ) err-unauthorized)
      
      ;; Update the right to inactive
      (map-set water-rights right-id (merge right { active: false }))
      
      ;; Log the deactivation event
      (print {
        event: "water-right-deactivated",
        right-id: right-id,
        deactivated-by: contract-caller,
        block-height: stacks-block-height
      })
      
      (ok true)
    )
  )
)
