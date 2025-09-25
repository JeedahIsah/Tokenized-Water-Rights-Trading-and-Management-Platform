;; Title: Usage Reporting Contract
;; Description: Allows right holders to report actual water usage with validator verification
;; Version: 1.0.0
;; Author: Water Rights Platform Team
;; License: MIT

;; This contract enables water rights holders to report their actual water consumption
;; and allows authorized validators to verify these reports. This creates accountability
;; and ensures compliance with allocated water rights.

;; ===== CONSTANTS =====

;; Contract owner (deployer)
(define-constant contract-owner tx-sender)

;; Error codes
(define-constant err-unauthorized (err u100))
(define-constant err-report-not-found (err u101))
(define-constant err-already-verified (err u102))
(define-constant err-invalid-volume (err u103))
(define-constant err-invalid-right-id (err u104))
(define-constant err-report-expired (err u105))
(define-constant err-cannot-verify-own-report (err u106))
(define-constant err-validator-not-authorized (err u107))
(define-constant err-reporting-disabled (err u108))
(define-constant err-duplicate-report (err u109))

;; Maximum values for validation
(define-constant max-usage-volume u1000000000) ;; 1 billion liters max per report
(define-constant report-validity-period u1440) ;; ~10 days in blocks (10 min blocks)
(define-constant max-reports-per-period u100) ;; Max reports per user per period

;; ===== DATA STRUCTURES =====

;; Counter for generating unique report IDs
(define-data-var next-report-id uint u1)

;; System operational status
(define-data-var reporting-enabled bool true)

;; Registry of authorized validators
(define-map authorized-validators principal bool)

;; Main usage reports mapping
(define-map usage-reports uint {
  right-id: uint,                 ;; ID of the water right being reported
  reported-by: principal,         ;; Address of the reporter
  volume-used: uint,              ;; Volume of water used in liters
  reporting-period: uint,         ;; Block height representing the reporting period
  timestamp: uint,                ;; Block height when report was submitted
  verified: bool,                 ;; Whether the report has been verified
  verified-by: (optional principal), ;; Validator who verified the report
  verified-at: (optional uint),   ;; Block height when verification occurred
  notes: (string-ascii 200)      ;; Additional notes or metadata
})

;; Track reports by right holder for easy querying
(define-map holder-reports principal (list 100 uint))

;; Track reports by water right ID
(define-map right-reports uint (list 50 uint))

;; Verification records for detailed tracking
(define-map verifications uint {
  report-id: uint,
  validator: principal,
  approved: bool,
  verification-notes: (string-ascii 200),
  verified-at: uint
})

;; Track validator activity
(define-map validator-stats principal {
  total-verifications: uint,
  approved-verifications: uint,
  rejected-verifications: uint
})

;; Prevent duplicate reports for same period
(define-map period-reports { right-id: uint, period: uint, reporter: principal } uint)

;; ===== PRIVATE FUNCTIONS =====

;; Validates that a volume amount is within acceptable limits
(define-private (is-valid-volume (volume uint))
  (and (> volume u0) (<= volume max-usage-volume))
)

;; Checks if reporting is currently enabled
(define-private (is-reporting-enabled)
  (var-get reporting-enabled)
)

;; Checks if a validator is authorized
(define-private (is-authorized-validator (validator principal))
  (default-to false (map-get? authorized-validators validator))
)

;; Calculates the reporting period based on block height
(define-private (get-reporting-period (height uint))
  ;; Group reports into weekly periods (1008 blocks = ~1 week)
  (/ height u1008)
)

;; Adds a report ID to holder's report list
(define-private (add-report-to-holder (holder principal) (report-id uint))
  (let ((current-reports (default-to (list) (map-get? holder-reports holder))))
    (map-set holder-reports holder 
      (unwrap! (as-max-len? (append current-reports report-id) u100) false))
  )
)

;; Adds a report ID to right's report list
(define-private (add-report-to-right (right-id uint) (report-id uint))
  (let ((current-reports (default-to (list) (map-get? right-reports right-id))))
    (map-set right-reports right-id 
      (unwrap! (as-max-len? (append current-reports report-id) u50) false))
  )
)

;; Updates validator statistics
(define-private (update-validator-stats (validator principal) (approved bool))
  (let ((current-stats (default-to { total-verifications: u0, approved-verifications: u0, rejected-verifications: u0 } 
                                   (map-get? validator-stats validator))))
    (map-set validator-stats validator {
      total-verifications: (+ (get total-verifications current-stats) u1),
      approved-verifications: (if approved 
        (+ (get approved-verifications current-stats) u1)
        (get approved-verifications current-stats)),
      rejected-verifications: (if approved 
        (get rejected-verifications current-stats)
        (+ (get rejected-verifications current-stats) u1))
    })
  )
)

;; ===== READ-ONLY FUNCTIONS =====

;; Gets a specific usage report by ID
(define-read-only (get-usage-report (report-id uint))
  (map-get? usage-reports report-id)
)

;; Gets all reports by a specific holder
(define-read-only (get-holder-reports (holder principal))
  (default-to (list) (map-get? holder-reports holder))
)

;; Gets all reports for a specific water right
(define-read-only (get-right-reports (right-id uint))
  (default-to (list) (map-get? right-reports right-id))
)

;; Gets verification details for a report
(define-read-only (get-verification (report-id uint))
  (map-get? verifications report-id)
)

;; Gets validator statistics
(define-read-only (get-validator-stats (validator principal))
  (map-get? validator-stats validator)
)

;; Gets the next available report ID
(define-read-only (get-next-report-id)
  (var-get next-report-id)
)

;; Checks if reporting is enabled
(define-read-only (get-reporting-status)
  (var-get reporting-enabled)
)

;; Checks if a validator is authorized
(define-read-only (is-validator-authorized (validator principal))
  (is-authorized-validator validator)
)

;; Gets the current reporting period
(define-read-only (get-current-reporting-period)
  (get-reporting-period stacks-block-height)
)

;; Checks if a report exists for a specific period
(define-read-only (has-period-report (right-id uint) (period uint) (reporter principal))
  (is-some (map-get? period-reports { right-id: right-id, period: period, reporter: reporter }))
)

;; ===== PUBLIC FUNCTIONS =====

;; Authorizes a new validator (only contract owner)
(define-public (authorize-validator (validator principal))
  (begin
    ;; Only contract owner can authorize validators
    (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
    
    ;; Add validator to authorized list
    (map-set authorized-validators validator true)
    
    ;; Log the authorization event
    (print {
      event: "validator-authorized",
      validator: validator,
      authorized-by: contract-caller,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Revokes validator authorization (only contract owner)
(define-public (revoke-validator (validator principal))
  (begin
    ;; Only contract owner can revoke validators
    (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
    
    ;; Remove validator from authorized list
    (map-set authorized-validators validator false)
    
    ;; Log the revocation event
    (print {
      event: "validator-revoked",
      validator: validator,
      revoked-by: contract-caller,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Submits a new usage report
(define-public (submit-usage-report 
  (right-id uint) 
  (volume-used uint) 
  (notes (string-ascii 200)))
  (let ((report-id (var-get next-report-id))
        (current-period (get-reporting-period stacks-block-height))
        (period-key { right-id: right-id, period: current-period, reporter: contract-caller }))
    (begin
      ;; Validate reporting is enabled
      (asserts! (is-reporting-enabled) err-reporting-disabled)
      
      ;; Validate input parameters
      (asserts! (> right-id u0) err-invalid-right-id)
      (asserts! (is-valid-volume volume-used) err-invalid-volume)
      
      ;; Check for duplicate report in same period
      (asserts! (not (has-period-report right-id current-period contract-caller)) err-duplicate-report)
      
      ;; Create the usage report
      (map-set usage-reports report-id {
        right-id: right-id,
        reported-by: contract-caller,
        volume-used: volume-used,
        reporting-period: current-period,
        timestamp: stacks-block-height,
        verified: false,
        verified-by: none,
        verified-at: none,
        notes: notes
      })
      
      ;; Track period report to prevent duplicates
      (map-set period-reports period-key report-id)
      
      ;; Add report to holder's list
      (add-report-to-holder contract-caller report-id)
      
      ;; Add report to right's list
      (add-report-to-right right-id report-id)
      
      ;; Increment report ID counter
      (var-set next-report-id (+ report-id u1))
      
      ;; Log the report submission event
      (print {
        event: "usage-report-submitted",
        report-id: report-id,
        right-id: right-id,
        reported-by: contract-caller,
        volume-used: volume-used,
        reporting-period: current-period,
        notes: notes,
        block-height: stacks-block-height
      })
      
      (ok report-id)
    )
  )
)

;; Verifies a usage report (only authorized validators)
(define-public (verify-usage-report (report-id uint) (approved bool) (verification-notes (string-ascii 200)))
  (let ((report (unwrap! (map-get? usage-reports report-id) err-report-not-found)))
    (begin
      ;; Validate caller is authorized validator
      (asserts! (is-authorized-validator contract-caller) err-validator-not-authorized)
      
      ;; Validator cannot verify their own report
      (asserts! (not (is-eq contract-caller (get reported-by report))) err-cannot-verify-own-report)
      
      ;; Report must not be already verified
      (asserts! (not (get verified report)) err-already-verified)
      
      ;; Report must not be expired
      (asserts! (<= (- stacks-block-height (get timestamp report)) report-validity-period) err-report-expired)
      
      ;; Update the report with verification status
      (map-set usage-reports report-id (merge report {
        verified: true,
        verified-by: (some contract-caller),
        verified-at: (some stacks-block-height)
      }))
      
      ;; Create verification record
      (map-set verifications report-id {
        report-id: report-id,
        validator: contract-caller,
        approved: approved,
        verification-notes: verification-notes,
        verified-at: stacks-block-height
      })
      
      ;; Update validator statistics
      (update-validator-stats contract-caller approved)
      
      ;; Log the verification event
      (print {
        event: "usage-report-verified",
        report-id: report-id,
        validator: contract-caller,
        approved: approved,
        verification-notes: verification-notes,
        block-height: stacks-block-height
      })
      
      (ok true)
    )
  )
)

;; Enables or disables reporting (only contract owner)
(define-public (set-reporting-status (enabled bool))
  (begin
    ;; Only contract owner can change reporting status
    (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
    
    ;; Update reporting status
    (var-set reporting-enabled enabled)
    
    ;; Log the status change event
    (print {
      event: "reporting-status-changed",
      enabled: enabled,
      changed-by: contract-caller,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Updates a report's notes (only original reporter, before verification)
(define-public (update-report-notes (report-id uint) (new-notes (string-ascii 200)))
  (let ((report (unwrap! (map-get? usage-reports report-id) err-report-not-found)))
    (begin
      ;; Only original reporter can update
      (asserts! (is-eq contract-caller (get reported-by report)) err-unauthorized)
      
      ;; Report must not be verified yet
      (asserts! (not (get verified report)) err-already-verified)
      
      ;; Update the report notes
      (map-set usage-reports report-id (merge report { notes: new-notes }))
      
      ;; Log the update event
      (print {
        event: "report-notes-updated",
        report-id: report-id,
        updated-by: contract-caller,
        new-notes: new-notes,
        block-height: stacks-block-height
      })
      
      (ok true)
    )
  )
)
