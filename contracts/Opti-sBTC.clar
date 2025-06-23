
;; Implements decentralized peer-to-peer options trading with internal BTC tracking

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-EXPIRED (err u1))
(define-constant ERR-INVALID-AMOUNT (err u2))
(define-constant ERR-UNAUTHORIZED (err u3))
(define-constant ERR-NOT-FOUND (err u4))
(define-constant ERR-INSUFFICIENT-BALANCE (err u5))
(define-constant ERR-ALREADY-EXECUTED (err u6))
(define-constant ERR-INVALID-PRICE (err u7))
(define-constant ERR-OPTION-NOT-ACTIVE (err u8))

;; Option Types
(define-constant CALL u1)
(define-constant PUT u2)

;; Data Maps
(define-map BTCBalances 
    { holder: principal }
    { balance: uint }
)

(define-map Options
    { option-id: uint }
    {
        creator: principal,
        buyer: (optional principal),
        option-type: uint,
        strike-price: uint,
        premium: uint,
        expiry: uint,
        btc-amount: uint,
        is-active: bool,
        is-executed: bool,
        creation-height: uint
    }
)

(define-map UserOptions
    { user: principal }
    { created: (list 20 uint), purchased: (list 20 uint) }
)

;; Data Variables
(define-data-var next-option-id uint u0)
(define-data-var oracle-price uint u0)

;; Authorization
(define-private (is-contract-owner)
    (is-eq tx-sender CONTRACT-OWNER)
)

;; BTC Balance Management
(define-public (deposit-btc (amount uint))
    (let
        ((sender tx-sender)
         (current-balance (default-to { balance: u0 } (map-get? BTCBalances { holder: sender }))))
        (map-set BTCBalances
            { holder: sender }
            { balance: (+ amount (get balance current-balance)) })
        (ok true)
    )
)

(define-public (withdraw-btc (amount uint))
    (let
        ((sender tx-sender)
         (current-balance (default-to { balance: u0 } (map-get? BTCBalances { holder: sender }))))
        (asserts! (>= (get balance current-balance) amount) ERR-INSUFFICIENT-BALANCE)
        (map-set BTCBalances
            { holder: sender }
            { balance: (- (get balance current-balance) amount) })
        (ok true)
    )
)

(define-private (transfer-btc (from principal) (to principal) (amount uint))
    (let
        ((from-balance (default-to { balance: u0 } (map-get? BTCBalances { holder: from })))
         (to-balance (default-to { balance: u0 } (map-get? BTCBalances { holder: to }))))
        (asserts! (>= (get balance from-balance) amount) ERR-INSUFFICIENT-BALANCE)
        (map-set BTCBalances
            { holder: from }
            { balance: (- (get balance from-balance) amount) })
        (map-set BTCBalances
            { holder: to }
            { balance: (+ amount (get balance to-balance)) })
        (ok true)
    )
)

(define-private (update-user-options (user principal) (option-id uint) (is-creator bool))
    (let
        ((user-options (default-to 
            { created: (list ), purchased: (list ) }
            (map-get? UserOptions { user: user }))))
        (if is-creator
            (ok (map-set UserOptions
                { user: user }
                { created: (unwrap! (as-max-len? (append (get created user-options) option-id) u20) ERR-UNAUTHORIZED),
                  purchased: (get purchased user-options) }))
            (ok (map-set UserOptions
                { user: user }
                { created: (get created user-options),
                  purchased: (unwrap! (as-max-len? (append (get purchased user-options) option-id) u20) ERR-UNAUTHORIZED) })))
    )
)




;; Option Management
(define-public (create-option 
    (option-type uint)
    (strike-price uint)
    (premium uint)
    (expiry uint)
    (btc-amount uint))
    (let
        ((option-id (+ (var-get next-option-id) u1))
         (sender tx-sender)
         (current-balance (default-to { balance: u0 } (map-get? BTCBalances { holder: sender }))))

        ;; Validate inputs
        (asserts! (or (is-eq option-type CALL) (is-eq option-type PUT)) ERR-INVALID-AMOUNT)
        (asserts! (> strike-price u0) ERR-INVALID-PRICE)
        (asserts! (> premium u0) ERR-INVALID-PRICE)
        (asserts! (> expiry stacks-block-height) ERR-EXPIRED)
        (asserts! (> btc-amount u0) ERR-INVALID-AMOUNT)

        ;; For CALL options, ensure creator has enough BTC
        (asserts! (if (is-eq option-type CALL)
            (>= (get balance current-balance) btc-amount)
            true) ERR-INSUFFICIENT-BALANCE)

        ;; Create option
        (map-set Options
            { option-id: option-id }
            {
                creator: sender,
                buyer: none,
                option-type: option-type,
                strike-price: strike-price,
                premium: premium,
                expiry: expiry,
                btc-amount: btc-amount,
                is-active: true,
                is-executed: false,
                creation-height: stacks-block-height
            })

    ;; Lock BTC for CALL options and update state
        (match (if (is-eq option-type CALL)
                (transfer-btc sender (as-contract tx-sender) btc-amount)
                (ok true))
            success (begin
                (var-set next-option-id option-id)
                (try! (update-user-options sender option-id true))
                (ok option-id))
            error (err error))
    )
)



(define-public (exercise-option (option-id uint))
    (let
        ((option (unwrap! (map-get? Options { option-id: option-id }) ERR-NOT-FOUND))
         (holder tx-sender))

        ;; Validate option state
        (asserts! (is-eq (some holder) (get buyer option)) ERR-UNAUTHORIZED)
        (asserts! (not (get is-executed option)) ERR-ALREADY-EXECUTED)
        (asserts! (< stacks-block-height (get expiry option)) ERR-EXPIRED)

        ;; Exercise based on option type
        (if (is-eq (get option-type option) CALL)
            (try! (exercise-call option holder))
            (try! (exercise-put option holder)))

        ;; Update option state
        (map-set Options
            { option-id: option-id }
            (merge option { is-executed: true }))
        (ok true)
    )
)

;; Private helper functions
(define-private (exercise-call
    (option {
        creator: principal,
        buyer: (optional principal),
        option-type: uint,
        strike-price: uint,
        premium: uint,
        expiry: uint,
        btc-amount: uint,
        is-active: bool,
        is-executed: bool,
        creation-height: uint
    })
    (holder principal))
    (let
        ((strike-amount (* (get strike-price option) (get btc-amount option))))
        ;; Transfer strike price from holder to creator
        (try! (stx-transfer? strike-amount holder (get creator option)))
        ;; Transfer BTC from contract to holder
        (as-contract (transfer-btc tx-sender holder (get btc-amount option)))
    )
)

(define-private (exercise-put
    (option {
        creator: principal,
        buyer: (optional principal),
        option-type: uint,
        strike-price: uint,
        premium: uint,
        expiry: uint,
        btc-amount: uint,
        is-active: bool,
        is-executed: bool,
        creation-height: uint
    })
    (holder principal))
    (let
        ((strike-amount (* (get strike-price option) (get btc-amount option))))
        ;; Transfer strike price from creator to holder
        (try! (stx-transfer? strike-amount (get creator option) holder))
        ;; Transfer BTC from contract to creator
        (as-contract (transfer-btc tx-sender (get creator option) (get btc-amount option)))
    )
)




;; Read-only functions
(define-read-only (get-option (option-id uint))
    (map-get? Options { option-id: option-id })
)

(define-read-only (get-btc-balance (holder principal))
    (default-to { balance: u0 }
        (map-get? BTCBalances { holder: holder }))
)

(define-read-only (get-user-options (user principal))
    (default-to
        { created: (list ), purchased: (list ) }
        (map-get? UserOptions { user: user }))
)

;; Oracle functions
(define-public (set-btc-price (price uint))
    (begin
        (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
        (var-set oracle-price price)
        (ok true))
)

(define-read-only (get-btc-price)
    (var-get oracle-price)
)