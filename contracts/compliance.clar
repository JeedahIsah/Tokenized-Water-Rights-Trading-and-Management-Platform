;; Title: Compliance Contract
;; Description: Enforces water usage compliance, tracks violations, and manages penalties
;; Version: 1.0.0
;; Author: Water Rights Platform Team
;; License: MIT

;; This contract manages compliance enforcement for water rights holders.
;; It tracks violations, applies penalties, and can revoke rights for serious breaches.
;; The contract is independent and reads from external usage data.

;; ===== CONSTANTS =====

;; Contract owner (deployer)
(define-constant contract-owner tx-sender)

;; Error codes
(define-constant err-unauthorized (err u200))
(define-constant err-invalid-right-id (err u201))
(define-constant err-invalid-volume (err u202))
(define-constant err-right-not-found (err u203))
(define-constant err-already-violated (err u204))
(define-constant err-invalid-penalty (err u205))
(define-constant err-right-already-revoked (err u206))

;; Compliance thresholds
(define-constant violation-threshold-percent u110) ;; 110% of allocated = violation
(define-constant max-violations-before-revocation u3)
(define-constant penalty-multiplier u10) ;; 10% penalty per violation

;; ===== DATA STRUCTURES =====

;; Counter for generating unique violation IDs
(define-data-var next-violation-id uint u1)

;; Counter for generating unique penalty IDs
(define-data-var next-penalty-id uint u1)

;; Track violations per right holder
(define-map violations uint {
  right-id: uint,
  holder: principal,
  violation-type: (string-ascii 50),
  volume-used: uint,
  volume-allocated: uint,
  reported-at: uint,
  severity: uint ;; 1-5 scale
})

;; Track penalties applied
(define-map penalties uint {
  violation-id: uint,
  holder: principal,
  penalty-amount: uint,
  penalty-type: (string-ascii 50),
  applied-at: uint,
  active: bool
})

;; Track revoked rights
(define-map revoked-rights uint {
  right-id: uint,
  holder: principal,
  reason: (string-ascii 100),
  revoked-at: uint,
  revoked-by: principal
})

;; Track compliance score per holder
(define-map compliance-scores principal {
  total-violations: uint,
  total-penalties: uint,
  rights-revoked: uint,
  last-violation: uint
})

;; ===== PRIVATE FUNCTIONS =====

;; Validates that a volume is positive
(define-private (is-valid-volume (volume uint))
  (> volume u0)
)

;; Calculates penalty amount based on violation severity
(define-private (calculate-penalty (volume-excess uint) (severity uint))
  (/ (* volume-excess penalty-multiplier severity) u100)
)

;; Updates compliance score for a holder
(define-private (update-compliance-score (holder principal) (violation-count uint) (penalty-count uint))
  (let ((current-score (default-to 
    { total-violations: u0, total-penalties: u0, rights-revoked: u0, last-violation: u0 }
    (map-get? compliance-scores holder))))
    (map-set compliance-scores holder {
      total-violations: (+ (get total-violations current-score) violation-count),
      total-penalties: (+ (get total-penalties current-score) penalty-count),
      rights-revoked: (get rights-revoked current-score),
      last-violation: stacks-block-height
    })
  )
)

;; ===== READ-ONLY FUNCTIONS =====

;; Gets violation details by ID
(define-read-only (get-violation (violation-id uint))
  (map-get? violations violation-id)
)

;; Gets penalty details by ID
(define-read-only (get-penalty (penalty-id uint))
  (map-get? penalties penalty-id)
)

;; Gets compliance score for a holder
(define-read-only (get-compliance-score (holder principal))
  (default-to 
    { total-violations: u0, total-penalties: u0, rights-revoked: u0, last-violation: u0 }
    (map-get? compliance-scores holder)
  )
)

;; Checks if a right is revoked
(define-read-only (is-right-revoked (right-id uint))
  (is-some (map-get? revoked-rights right-id))
)

;; Gets revocation details
(define-read-only (get-revocation (right-id uint))
  (map-get? revoked-rights right-id)
)

;; ===== PUBLIC FUNCTIONS =====

;; Records a usage violation
(define-public (record-violation 
  (right-id uint) 
  (holder principal) 
  (volume-used uint) 
  (volume-allocated uint) 
  (severity uint))
  (let ((violation-id (var-get next-violation-id)))
    (begin
      ;; Only contract owner can record violations
      (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
      
      ;; Validate inputs
      (asserts! (is-valid-volume volume-used) err-invalid-volume)
      (asserts! (is-valid-volume volume-allocated) err-invalid-volume)
      (asserts! (and (> severity u0) (<= severity u5)) err-invalid-penalty)
      
      ;; Record the violation
      (map-set violations violation-id {
        right-id: right-id,
        holder: holder,
        violation-type: "over-usage",
        volume-used: volume-used,
        volume-allocated: volume-allocated,
        reported-at: stacks-block-height,
        severity: severity
      })
      
      ;; Update compliance score
      (update-compliance-score holder u1 u0)
      
      ;; Increment violation ID
      (var-set next-violation-id (+ violation-id u1))
      
      ;; Log the violation event
      (print {
        event: "violation-recorded",
        violation-id: violation-id,
        right-id: right-id,
        holder: holder,
        volume-used: volume-used,
        volume-allocated: volume-allocated,
        severity: severity,
        block-height: stacks-block-height
      })
      
      (ok violation-id)
    )
  )
)

;; Applies a penalty for a violation
(define-public (apply-penalty (violation-id uint) (penalty-type (string-ascii 50)))
  (let ((violation (unwrap! (map-get? violations violation-id) err-invalid-right-id))
        (penalty-id (var-get next-penalty-id))
        (excess-volume (- (get volume-used violation) (get volume-allocated violation)))
        (penalty-amount (calculate-penalty excess-volume (get severity violation))))
    (begin
      ;; Only contract owner can apply penalties
      (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
      
      ;; Record the penalty
      (map-set penalties penalty-id {
        violation-id: violation-id,
        holder: (get holder violation),
        penalty-amount: penalty-amount,
        penalty-type: penalty-type,
        applied-at: stacks-block-height,
        active: true
      })
      
      ;; Update compliance score
      (update-compliance-score (get holder violation) u0 u1)
      
      ;; Increment penalty ID
      (var-set next-penalty-id (+ penalty-id u1))
      
      ;; Log the penalty event
      (print {
        event: "penalty-applied",
        penalty-id: penalty-id,
        violation-id: violation-id,
        holder: (get holder violation),
        penalty-amount: penalty-amount,
        penalty-type: penalty-type,
        block-height: stacks-block-height
      })
      
      (ok penalty-id)
    )
  )
)

;; Revokes a water right for serious violations
(define-public (revoke-right (right-id uint) (holder principal) (reason (string-ascii 100)))
  (let ((revocation-id right-id))
    (begin
      ;; Only contract owner can revoke rights
      (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
      
      ;; Check if already revoked
      (asserts! (not (is-right-revoked right-id)) err-right-already-revoked)
      
      ;; Record the revocation
      (map-set revoked-rights revocation-id {
        right-id: right-id,
        holder: holder,
        reason: reason,
        revoked-at: stacks-block-height,
        revoked-by: contract-caller
      })
      
      ;; Update compliance score
      (let ((current-score (get-compliance-score holder)))
        (map-set compliance-scores holder {
          total-violations: (get total-violations current-score),
          total-penalties: (get total-penalties current-score),
          rights-revoked: (+ (get rights-revoked current-score) u1),
          last-violation: stacks-block-height
        })
      )
      
      ;; Log the revocation event
      (print {
        event: "right-revoked",
        right-id: right-id,
        holder: holder,
        reason: reason,
        revoked-by: contract-caller,
        block-height: stacks-block-height
      })
      
      (ok true)
    )
  )
)

