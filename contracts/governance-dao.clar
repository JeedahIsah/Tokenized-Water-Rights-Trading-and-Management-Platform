;; Title: Governance DAO Contract
;; Description: Enables stakeholder voting on governance proposals and policy changes
;; Version: 1.0.0
;; Author: Water Rights Platform Team
;; License: MIT

;; This contract implements a decentralized autonomous organization (DAO) for governance.
;; Stakeholders can create proposals, vote on them, and execute approved changes.
;; Voting is token-weighted based on governance token holdings.

;; ===== CONSTANTS =====

;; Contract owner (deployer)
(define-constant contract-owner tx-sender)

;; Error codes
(define-constant err-unauthorized (err u300))
(define-constant err-invalid-proposal-id (err u301))
(define-constant err-proposal-not-found (err u302))
(define-constant err-proposal-expired (err u303))
(define-constant err-already-voted (err u304))
(define-constant err-invalid-duration (err u305))
(define-constant err-proposal-not-approved (err u306))
(define-constant err-proposal-already-executed (err u307))

;; Governance parameters
(define-constant min-proposal-duration u100) ;; Minimum 100 blocks
(define-constant max-proposal-duration u52560) ;; Maximum ~1 year
(define-constant quorum-percent u20) ;; 20% participation required
(define-constant approval-threshold-percent u50) ;; 50% approval required

;; ===== DATA STRUCTURES =====

;; Counter for generating unique proposal IDs
(define-data-var next-proposal-id uint u1)

;; Proposal states: 0=pending, 1=active, 2=approved, 3=rejected, 4=executed
(define-map proposals uint {
  proposer: principal,
  title: (string-ascii 100),
  description: (string-ascii 500),
  proposal-type: (string-ascii 50),
  created-at: uint,
  voting-ends-at: uint,
  yes-votes: uint,
  no-votes: uint,
  total-voters: uint,
  state: uint,
  executed: bool
})

;; Track votes per proposal per voter
(define-map votes { proposal-id: uint, voter: principal } bool)

;; Track voting power per principal
(define-map voting-power principal uint)

;; ===== PRIVATE FUNCTIONS =====

;; Validates proposal duration
(define-private (is-valid-duration (duration uint))
  (and (>= duration min-proposal-duration) (<= duration max-proposal-duration))
)

;; Checks if a proposal is still active for voting
(define-private (is-proposal-active (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (and 
      (< stacks-block-height (get voting-ends-at proposal))
      (is-eq (get state proposal) u1)
    )
    false
  )
)

;; Calculates if a proposal meets approval threshold
(define-private (is-proposal-approved (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (if (> (get total-voters proposal) u0)
      (>= (* (get yes-votes proposal) u100) 
          (* (get total-voters proposal) approval-threshold-percent))
      false
    )
    false
  )
)

;; ===== READ-ONLY FUNCTIONS =====

;; Gets proposal details by ID
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

;; Gets voting power for a principal
(define-read-only (get-voting-power (voter principal))
  (default-to u0 (map-get? voting-power voter))
)

;; Checks if a voter has already voted on a proposal
(define-read-only (has-voted (proposal-id uint) (voter principal))
  (is-some (map-get? votes { proposal-id: proposal-id, voter: voter }))
)

;; Gets the next proposal ID
(define-read-only (get-next-proposal-id)
  (var-get next-proposal-id)
)

;; ===== PUBLIC FUNCTIONS =====

;; Allocates voting power to a principal (only contract owner)
(define-public (allocate-voting-power (voter principal) (power uint))
  (begin
    ;; Only contract owner can allocate voting power
    (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
    
    ;; Set voting power
    (map-set voting-power voter power)
    
    ;; Log the allocation event
    (print {
      event: "voting-power-allocated",
      voter: voter,
      power: power,
      allocated-by: contract-caller,
      block-height: stacks-block-height
    })
    
    (ok true)
  )
)

;; Creates a new governance proposal
(define-public (create-proposal 
  (title (string-ascii 100)) 
  (description (string-ascii 500)) 
  (proposal-type (string-ascii 50)) 
  (duration uint))
  (let ((proposal-id (var-get next-proposal-id))
        (voting-ends-at (+ stacks-block-height duration)))
    (begin
      ;; Validate duration
      (asserts! (is-valid-duration duration) err-invalid-duration)
      
      ;; Create the proposal
      (map-set proposals proposal-id {
        proposer: contract-caller,
        title: title,
        description: description,
        proposal-type: proposal-type,
        created-at: stacks-block-height,
        voting-ends-at: voting-ends-at,
        yes-votes: u0,
        no-votes: u0,
        total-voters: u0,
        state: u1,
        executed: false
      })
      
      ;; Increment proposal ID
      (var-set next-proposal-id (+ proposal-id u1))
      
      ;; Log the proposal creation event
      (print {
        event: "proposal-created",
        proposal-id: proposal-id,
        proposer: contract-caller,
        title: title,
        proposal-type: proposal-type,
        voting-ends-at: voting-ends-at,
        block-height: stacks-block-height
      })
      
      (ok proposal-id)
    )
  )
)

;; Casts a vote on a proposal
(define-public (vote (proposal-id uint) (vote-yes bool))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
        (voter-power (get-voting-power contract-caller)))
    (begin
      ;; Validate proposal is active
      (asserts! (is-proposal-active proposal-id) err-proposal-expired)
      
      ;; Check voter hasn't already voted
      (asserts! (not (has-voted proposal-id contract-caller)) err-already-voted)
      
      ;; Voter must have voting power
      (asserts! (> voter-power u0) err-unauthorized)
      
      ;; Record the vote
      (map-set votes { proposal-id: proposal-id, voter: contract-caller } vote-yes)
      
      ;; Update proposal vote counts
      (let ((new-yes-votes (if vote-yes (+ (get yes-votes proposal) voter-power) (get yes-votes proposal)))
            (new-no-votes (if vote-yes (get no-votes proposal) (+ (get no-votes proposal) voter-power))))
        (map-set proposals proposal-id (merge proposal {
          yes-votes: new-yes-votes,
          no-votes: new-no-votes,
          total-voters: (+ (get total-voters proposal) u1)
        }))
      )
      
      ;; Log the vote event
      (print {
        event: "vote-cast",
        proposal-id: proposal-id,
        voter: contract-caller,
        vote-yes: vote-yes,
        voter-power: voter-power,
        block-height: stacks-block-height
      })
      
      (ok true)
    )
  )
)

;; Finalizes a proposal after voting ends
(define-public (finalize-proposal (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found)))
    (begin
      ;; Voting period must have ended
      (asserts! (>= stacks-block-height (get voting-ends-at proposal)) err-proposal-expired)
      
      ;; Proposal must not be executed
      (asserts! (not (get executed proposal)) err-proposal-already-executed)
      
      ;; Update proposal state based on approval
      (let ((new-state (if (is-proposal-approved proposal-id) u2 u3)))
        (map-set proposals proposal-id (merge proposal { state: new-state }))
      )
      
      ;; Log the finalization event
      (print {
        event: "proposal-finalized",
        proposal-id: proposal-id,
        yes-votes: (get yes-votes proposal),
        no-votes: (get no-votes proposal),
        approved: (is-proposal-approved proposal-id),
        block-height: stacks-block-height
      })
      
      (ok true)
    )
  )
)

;; Executes an approved proposal (only contract owner)
(define-public (execute-proposal (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found)))
    (begin
      ;; Only contract owner can execute
      (asserts! (is-eq contract-caller contract-owner) err-unauthorized)
      
      ;; Proposal must be approved
      (asserts! (is-eq (get state proposal) u2) err-proposal-not-approved)
      
      ;; Proposal must not be executed
      (asserts! (not (get executed proposal)) err-proposal-already-executed)
      
      ;; Mark as executed
      (map-set proposals proposal-id (merge proposal { executed: true }))
      
      ;; Log the execution event
      (print {
        event: "proposal-executed",
        proposal-id: proposal-id,
        proposal-type: (get proposal-type proposal),
        executed-by: contract-caller,
        block-height: stacks-block-height
      })
      
      (ok true)
    )
  )
)

