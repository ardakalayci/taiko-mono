// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.20;

import { AddressResolver } from "../../common/AddressResolver.sol";
import { EtherVault } from "../EtherVault.sol";
import { IRecallableMessageSender, IBridge } from "../IBridge.sol";
import { LibBridgeData } from "./LibBridgeData.sol";
import { LibBridgeStatus } from "./LibBridgeStatus.sol";
import { LibAddress } from "../../libs/LibAddress.sol";

/**
 * This library provides functions for releasing Ether (and tokens) related to
 * message
 * execution on the Bridge.
 */

library LibBridgeRecall {
    using LibBridgeData for IBridge.Message;
    using LibAddress for address;

    event MessageRecalled(bytes32 indexed msgHash);

    error B_MSG_NOT_FAILED();
    error B_MSG_RECALLED_ALREADY();

    /**
     * /**
     * Recall a failed message on its source chain.
     * @dev This function will potentially release any Ether or tokens locked.
     * @param state The current state of the Bridge
     * @param resolver The AddressResolver instance
     * @param message The message whose associated Ether should be released
     * @param proof The proof data
     * @param checkProof Indicating if checking the proof or not (test version)
     */
    function recallMessage(
        LibBridgeData.State storage state,
        AddressResolver resolver,
        IBridge.Message calldata message,
        bytes calldata proof,
        bool checkProof
    )
        internal
    {
        bytes32 msgHash = message.hashMessage();

        if (state.recalls[msgHash]) {
            revert B_MSG_RECALLED_ALREADY();
        }

        if (
            checkProof
                && !LibBridgeStatus.isMessageFailed(
                    resolver, msgHash, message.destChainId, proof
                )
        ) {
            revert B_MSG_NOT_FAILED();
        }

        state.recalls[msgHash] = true;

        // We retrieve the necessary ether from EtherVault if receiving on
        // Taiko, otherwise it is already available in this Bridge.
        address ethVault = resolver.resolve("ether_vault", true);
        if (ethVault != address(0)) {
            EtherVault(payable(ethVault)).releaseEther(
                address(this), message.value
            );
        }
        if (
            message.from.supportsInterface(
                type(IRecallableMessageSender).interfaceId
            )
        ) {
            IRecallableMessageSender(message.from).onMessageRecalled{
                value: message.value
            }(message);
        } else {
            message.user.sendEther(message.value);
        }

        emit MessageRecalled(msgHash);
    }
}