;; DAO Salary Vesting
;; ----------------------------

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-INSUFFICIENT-FUNDS (err u403))
(define-constant ERR-EMERGENCY-PAUSE (err u405))
(define-constant ERR-INVALID-AMOUNT (err u406))

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var emergency-pause bool false)

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
        (map-set vesting-schedules recipient {
            total: total,
            claimed: u0,
            start-block: stacks-block-height,
            interval: interval,
            step: step,
        })
        (ok true)
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

;; Read-only Functions
(define-read-only (get-vesting-schedule (recipient principal))
    (map-get? vesting-schedules recipient)
)

(define-read-only (get-contract-owner)
    (var-get contract-owner)
)

(define-read-only (is-emergency-paused)
    (var-get emergency-pause)
)
