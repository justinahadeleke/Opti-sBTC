
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
