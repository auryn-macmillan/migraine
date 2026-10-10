object "FixedRateRedeemer" {
    code {
        mstore(64, 128)
        if callvalue() {
            revert(0, 0)
        }
        function internal_internal_preview(amountA) -> __ret0 {
            __ret0 := div(mul(amountA, 25), 10)
            leave
        }
        function internal_internal_redeem(amountA) {
            if iszero(gt(amountA, 0)) {
                mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                mstore(4, 32)
                mstore(36, 10)
                mstore(68, 0x5a65726f416d6f756e7400000000000000000000000000000000000000000000)
                revert(0, 100)
            }
            let amountB := div(mul(amountA, 25), 10)
            if iszero(gt(amountB, 0)) {
                mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                mstore(4, 32)
                mstore(36, 10)
                mstore(68, 0x5a65726f4f757470757400000000000000000000000000000000000000000000)
                revert(0, 100)
            }
            let inventory := sload(0)
            if lt(inventory, amountB) {
                mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                mstore(4, 32)
                mstore(36, 21)
                mstore(68, 0x496e73756666696369656e74496e76656e746f72790000000000000000000000)
                revert(0, 100)
            }
            if lt(inventory, amountB) {
                mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                mstore(4, 32)
                mstore(36, 19)
                mstore(68, 0x496e76656e746f727920756e646572666c6f7700000000000000000000000000)
                revert(0, 100)
            }
            let newInventory := sub(inventory, amountB)
            let redeemed := sload(1)
            if lt(add(redeemed, amountA), redeemed) {
                mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                mstore(4, 32)
                mstore(36, 17)
                mstore(68, 0x52656465656d6564206f766572666c6f77000000000000000000000000000000)
                revert(0, 100)
            }
            let newRedeemed := add(redeemed, amountA)
            sstore(0, newInventory)
            sstore(1, newRedeemed)
            stop()
        }
        let argsOffset := add(dataoffset("runtime"), datasize("runtime"))
        let argsSize := sub(codesize(), argsOffset)
        codecopy(0, argsOffset, argsSize)
        if lt(argsSize, 32) {
            revert(0, 0)
        }
        let initialInventory := mload(0)
        let arg0 := initialInventory
        sstore(0, initialInventory)
        sstore(1, 0)
        datacopy(0, dataoffset("runtime"), datasize("runtime"))
        return(0, datasize("runtime"))
    }
    object "runtime" {
        code {
            function internal_internal_preview(amountA) -> __ret0 {
                __ret0 := div(mul(amountA, 25), 10)
                leave
            }
            function internal_internal_redeem(amountA) {
                if iszero(gt(amountA, 0)) {
                    mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                    mstore(4, 32)
                    mstore(36, 10)
                    mstore(68, 0x5a65726f416d6f756e7400000000000000000000000000000000000000000000)
                    revert(0, 100)
                }
                let amountB := div(mul(amountA, 25), 10)
                if iszero(gt(amountB, 0)) {
                    mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                    mstore(4, 32)
                    mstore(36, 10)
                    mstore(68, 0x5a65726f4f757470757400000000000000000000000000000000000000000000)
                    revert(0, 100)
                }
                let inventory := sload(0)
                if lt(inventory, amountB) {
                    mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                    mstore(4, 32)
                    mstore(36, 21)
                    mstore(68, 0x496e73756666696369656e74496e76656e746f72790000000000000000000000)
                    revert(0, 100)
                }
                if lt(inventory, amountB) {
                    mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                    mstore(4, 32)
                    mstore(36, 19)
                    mstore(68, 0x496e76656e746f727920756e646572666c6f7700000000000000000000000000)
                    revert(0, 100)
                }
                let newInventory := sub(inventory, amountB)
                let redeemed := sload(1)
                if lt(add(redeemed, amountA), redeemed) {
                    mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                    mstore(4, 32)
                    mstore(36, 17)
                    mstore(68, 0x52656465656d6564206f766572666c6f77000000000000000000000000000000)
                    revert(0, 100)
                }
                let newRedeemed := add(redeemed, amountA)
                sstore(0, newInventory)
                sstore(1, newRedeemed)
                stop()
            }
            mstore(64, 128)
            {
                let __has_selector := iszero(lt(calldatasize(), 4))
                if iszero(__has_selector) {
                    revert(0, 0)
                }
                if __has_selector {
                    switch shr(224, calldataload(0))
                    case 0xc317c377 {
                        /* preview() */
                        if callvalue() {
                            revert(0, 0)
                        }
                        if lt(calldatasize(), 36) {
                            revert(0, 0)
                        }
                        if lt(calldatasize(), 36) {
                            revert(0, 0)
                        }
                        let amountA := calldataload(4)
                        mstore(0, div(mul(amountA, 25), 10))
                        return(0, 32)
                    }
                    case 0xdb006a75 {
                        /* redeem() */
                        if callvalue() {
                            revert(0, 0)
                        }
                        if lt(calldatasize(), 36) {
                            revert(0, 0)
                        }
                        if lt(calldatasize(), 36) {
                            revert(0, 0)
                        }
                        let amountA := calldataload(4)
                        if iszero(gt(amountA, 0)) {
                            mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                            mstore(4, 32)
                            mstore(36, 10)
                            mstore(68, 0x5a65726f416d6f756e7400000000000000000000000000000000000000000000)
                            revert(0, 100)
                        }
                        let amountB := div(mul(amountA, 25), 10)
                        if iszero(gt(amountB, 0)) {
                            mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                            mstore(4, 32)
                            mstore(36, 10)
                            mstore(68, 0x5a65726f4f757470757400000000000000000000000000000000000000000000)
                            revert(0, 100)
                        }
                        let inventory := sload(0)
                        if lt(inventory, amountB) {
                            mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                            mstore(4, 32)
                            mstore(36, 21)
                            mstore(68, 0x496e73756666696369656e74496e76656e746f72790000000000000000000000)
                            revert(0, 100)
                        }
                        if lt(inventory, amountB) {
                            mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                            mstore(4, 32)
                            mstore(36, 19)
                            mstore(68, 0x496e76656e746f727920756e646572666c6f7700000000000000000000000000)
                            revert(0, 100)
                        }
                        let newInventory := sub(inventory, amountB)
                        let redeemed := sload(1)
                        if lt(add(redeemed, amountA), redeemed) {
                            mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                            mstore(4, 32)
                            mstore(36, 17)
                            mstore(68, 0x52656465656d6564206f766572666c6f77000000000000000000000000000000)
                            revert(0, 100)
                        }
                        let newRedeemed := add(redeemed, amountA)
                        sstore(0, newInventory)
                        sstore(1, newRedeemed)
                        stop()
                    }
                    default {
                        revert(0, 0)
                    }
                }
            }
        }
    }
}