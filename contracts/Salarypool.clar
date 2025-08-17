;; DAO Salary Vesting
;; ----------------------------

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-INSUFFICIENT-FUNDS (err u403))
(define-constant ERR-EMERGENCY-PAUSE (err u405))
(define-constant ERR-INVALID-AMOUNT (err u406))
(define-constant ERR-INSUFFICIENT-SIGNATURES (err u407))
(define-constant ERR-ALREADY-SIGNED (err u408))
(define-constant ERR-TIMELOCK-NOT-EXPIRED (err u409))

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var emergency-pause bool false)
(define-data-var required-signatures uint u2)
(define-data-var total-vested uint u0)
(define-data-var total-claimed uint u0)
(define-data-var active-recipients-count uint u0)

;; Data Maps
(define-map vesting-schedules
    principal
    {
        total: uint,
        claimed: uint,
        start-block: uint,
        interval: uint,
        step: uint,
    }
)

;; Security Enhancement Maps
(define-map authorized-signers principal bool)
(define-map pending-operations 
    uint 
    {
        operation-type: (string-ascii 50),
        target: principal,
        amount: uint,
        execution-block: uint,
        signatures: (list 10 principal),
        executed: bool
    }
)
(define-data-var operation-nonce uint u0)

;; Recipients tracking for analytics
(define-map recipient-status principal bool)

;; Helper Functions
(define-private (is-owner)
    (is-eq tx-sender (var-get contract-owner))
)

(define-private (check-emergency-pause)
    (if (var-get emergency-pause)
        ERR-EMERGENCY-PAUSE
        (ok true)
    )
)

(define-private (is-authorized-signer)
    (default-to false (map-get? authorized-signers tx-sender))
)

(define-private (has-signed (operation-id uint) (signer principal))
    (match (map-get? pending-operations operation-id)
        operation (is-some (index-of (get signatures operation) signer))
        false
    )
)

(define-private (count-signatures (signatures (list 10 principal)))
    (len signatures)
)

(define-private (update-analytics-on-create (total uint))
    (begin
        (var-set total-vested (+ (var-get total-vested) total))
        (var-set active-recipients-count (+ (var-get active-recipients-count) u1))
    )
)

(define-private (update-analytics-on-claim (amount uint))
    (var-set total-claimed (+ (var-get total-claimed) amount))
)

;; Core Functions
(define-public (create-vesting
        (recipient principal)
        (total uint)
        (interval uint)
        (step uint)
    )
    (begin
        (try! (check-emergency-pause))
        (asserts! (is-owner) ERR-NOT-AUTHORIZED)
        (asserts! (> total u0) ERR-INVALID-AMOUNT)
        (asserts! (> interval u0) ERR-INVALID-AMOUNT)
        (asserts! (> step u0) ERR-INVALID-AMOUNT)
        (let ((is-new-recipient (is-none (map-get? vesting-schedules recipient))))
            (begin
                (map-set vesting-schedules recipient {
                    total: total,
                    claimed: u0,
                    start-block: stacks-block-height,
                    interval: interval,
                    step: step,
                })
                (map-set recipient-status recipient true)
                (if is-new-recipient
                    (update-analytics-on-create total)
                    true
                )
                (ok true)
            )
        )
    )
)

(define-public (claim-vested)
    (begin
        (try! (check-emergency-pause))
        (let ((schedule (map-get? vesting-schedules tx-sender)))
            (match schedule
                s (let (
                        (elapsed (/ (- stacks-block-height (get start-block s))
                            (get interval s)
                        ))
                        (max-claim (* elapsed (get step s)))
                        (available (- max-claim (get claimed s)))
                        (to-claim (if (> available (get total s))
                            (- (get total s) (get claimed s))
                            available
                        ))
                    )
                    (begin
                        (asserts! (> to-claim u0) ERR-INVALID-AMOUNT)
                        (map-set vesting-schedules tx-sender
                            (merge s { claimed: (+ (get claimed s) to-claim) })
                        )
                        (update-analytics-on-claim to-claim)
                        (stx-transfer? to-claim (as-contract tx-sender) tx-sender)
                    )
                )
                ERR-NOT-FOUND
            )
        )
    )
)

;; 5. Batch Operations
(define-public (create-multiple-vestings
        (recipients (list 50 principal))
        (totals (list 50 uint))
        (intervals (list 50 uint))
        (steps (list 50 uint))
    )
    (begin
        (try! (check-emergency-pause))
        (asserts! (is-owner) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (len recipients) (len totals)) ERR-INVALID-AMOUNT)
        (asserts! (is-eq (len recipients) (len intervals)) ERR-INVALID-AMOUNT)
        (asserts! (is-eq (len recipients) (len steps)) ERR-INVALID-AMOUNT)
        (ok (map create-single-vesting-batch recipients totals intervals steps))
    )
)

(define-private (create-single-vesting-batch
        (recipient principal)
        (total uint)
        (interval uint)
        (step uint)
    )
    (map-set vesting-schedules recipient {
        total: total,
        claimed: u0,
        start-block: stacks-block-height,
        interval: interval,
        step: step,
    })
)

;; 6. Treasury Management
(define-public (deposit-funds (amount uint))
    (begin
        (try! (check-emergency-pause))
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (stx-transfer? amount tx-sender (as-contract tx-sender))
    )
)

(define-public (withdraw-excess-funds (amount uint))
    (begin
        (try! (check-emergency-pause))
        (asserts! (is-owner) ERR-NOT-AUTHORIZED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= (stx-get-balance (as-contract tx-sender)) amount)
            ERR-INSUFFICIENT-FUNDS
        )
        (as-contract (stx-transfer? amount tx-sender (var-get contract-owner)))
    )
)

(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)

;; 8. Emergency Functions
(define-public (emergency-pause-contract)
    (begin
        (asserts! (is-owner) ERR-NOT-AUTHORIZED)
        (var-set emergency-pause true)
        (ok true)
    )
)

(define-public (emergency-resume-contract)
    (begin
        (asserts! (is-owner) ERR-NOT-AUTHORIZED)
        (var-set emergency-pause false)
        (ok true)
    )
)

(define-public (set-contract-owner (new-owner principal))
    (begin
        (asserts! (is-owner) ERR-NOT-AUTHORIZED)
        (var-set contract-owner new-owner)
        (ok true)
    )
)

;; Security Enhancement Functions - Multi-Signature Support
(define-public (add-authorized-signer (signer principal))
    (begin
        (asserts! (is-owner) ERR-NOT-AUTHORIZED)
        (map-set authorized-signers signer true)
        (ok true)
    )
)

(define-public (remove-authorized-signer (signer principal))
    (begin
        (asserts! (is-owner) ERR-NOT-AUTHORIZED)
        (map-delete authorized-signers signer)
        (ok true)
    )
)

(define-public (set-required-signatures (new-requirement uint))
    (begin
        (asserts! (is-owner) ERR-NOT-AUTHORIZED)
        (asserts! (> new-requirement u0) ERR-INVALID-AMOUNT)
        (var-set required-signatures new-requirement)
        (ok true)
    )
)

(define-public (propose-owner-change (new-owner principal) (execution-delay uint))
    (begin
        (asserts! (or (is-owner) (is-authorized-signer)) ERR-NOT-AUTHORIZED)
        (let ((operation-id (var-get operation-nonce)))
            (begin
                (map-set pending-operations operation-id {
                    operation-type: "owner-change",
                    target: new-owner,
                    amount: u0,
                    execution-block: (+ stacks-block-height execution-delay),
                    signatures: (list tx-sender),
                    executed: false
                })
                (var-set operation-nonce (+ operation-id u1))
                (ok operation-id)
            )
        )
    )
)

(define-public (sign-operation (operation-id uint))
    (begin
        (asserts! (is-authorized-signer) ERR-NOT-AUTHORIZED)
        (asserts! (not (has-signed operation-id tx-sender)) ERR-ALREADY-SIGNED)
        (match (map-get? pending-operations operation-id)
            operation (let ((updated-signatures (unwrap! (as-max-len? (append (get signatures operation) tx-sender) u10) ERR-INVALID-AMOUNT)))
                (begin
                    (map-set pending-operations operation-id
                        (merge operation { signatures: updated-signatures })
                    )
                    (ok true)
                )
            )
            ERR-NOT-FOUND
        )
    )
)

(define-public (execute-operation (operation-id uint))
    (begin
        (match (map-get? pending-operations operation-id)
            operation (begin
                (asserts! (not (get executed operation)) ERR-NOT-AUTHORIZED)
                (asserts! (>= stacks-block-height (get execution-block operation)) ERR-TIMELOCK-NOT-EXPIRED)
                (asserts! (>= (count-signatures (get signatures operation)) (var-get required-signatures)) ERR-INSUFFICIENT-SIGNATURES)
                (if (is-eq (get operation-type operation) "owner-change")
                    (begin
                        (var-set contract-owner (get target operation))
                        (map-set pending-operations operation-id
                            (merge operation { executed: true })
                        )
                        (ok true)
                    )
                    (ok false)
                )
            )
            ERR-NOT-FOUND
        )
    )
)

;; Reporting & Analytics Functions
(define-read-only (get-total-vested)
    (var-get total-vested)
)

(define-read-only (get-total-claimed)
    (var-get total-claimed)
)

(define-read-only (get-total-pending)
    (- (var-get total-vested) (var-get total-claimed))
)

(define-read-only (get-active-recipients-count)
    (var-get active-recipients-count)
)

(define-read-only (get-vesting-statistics)
    {
        total-vested: (var-get total-vested),
        total-claimed: (var-get total-claimed),
        total-pending: (- (var-get total-vested) (var-get total-claimed)),
        active-recipients: (var-get active-recipients-count),
        contract-balance: (stx-get-balance (as-contract tx-sender))
    }
)

(define-read-only (is-recipient-active (recipient principal))
    (default-to false (map-get? recipient-status recipient))
)

(define-read-only (get-recipient-vesting-progress (recipient principal))
    (match (map-get? vesting-schedules recipient)
        schedule (let (
                (progress-percentage (if (> (get total schedule) u0)
                    (/ (* (get claimed schedule) u100) (get total schedule))
                    u0
                ))
                (elapsed (/ (- stacks-block-height (get start-block schedule))
                    (get interval schedule)
                ))
                (max-claim (* elapsed (get step schedule)))
                (available (- max-claim (get claimed schedule)))
                (to-claim (if (> available (get total schedule))
                    (- (get total schedule) (get claimed schedule))
                    available
                ))
            )
            (some {
                progress-percentage: progress-percentage,
                claimed: (get claimed schedule),
                total: (get total schedule),
                available-to-claim: to-claim,
                next-vesting-block: (+ (get start-block schedule) 
                    (* (+ elapsed u1) (get interval schedule)))
            })
        )
        none
    )
)

;; Security Read-only Functions
(define-read-only (is-authorized-signer-check (signer principal))
    (default-to false (map-get? authorized-signers signer))
)

(define-read-only (get-required-signatures)
    (var-get required-signatures)
)

(define-read-only (get-pending-operation (operation-id uint))
    (map-get? pending-operations operation-id)
)

(define-read-only (get-operation-signature-count (operation-id uint))
    (match (map-get? pending-operations operation-id)
        operation (count-signatures (get signatures operation))
        u0
    )
)

;; Original Read-only Functions
(define-read-only (get-vesting-schedule (recipient principal))
    (map-get? vesting-schedules recipient)
)

(define-read-only (get-contract-owner)
    (var-get contract-owner)
)

(define-read-only (is-emergency-paused)
    (var-get emergency-pause)
)
