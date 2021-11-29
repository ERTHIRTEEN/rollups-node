// Copyright 2021 Cartesi Pte. Ltd.

// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use
// this file except in compliance with the License. You may obtain a copy of the
// License at http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software distributed
// under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

/// @title Rollups facet
pragma solidity ^0.8.0;

import {IRollups, Phase} from "../interfaces/IRollups.sol";
import {Result} from "../interfaces/IValidatorManager.sol";

import {LibRollups} from "../libraries/LibRollups.sol";
import {LibInput} from "../libraries/LibInput.sol";
import {LibOutput} from "../libraries/LibOutput.sol";
import {LibValidatorManager} from "../libraries/LibValidatorManager.sol";

contract RollupsFacet is IRollups {
    /// @notice claim the result of current epoch
    /// @param _epochHash hash of epoch
    /// @dev ValidatorManager makes sure that msg.sender is allowed
    //       and that claim != bytes32(0)
    /// TODO: add signatures for aggregated claims
    function claim(bytes32 _epochHash) public override {
        LibRollups.DiamondStorage storage ds = LibRollups.diamondStorage();

        Result result;
        bytes32[2] memory claims;
        address payable[2] memory claimers;

        Phase currentPhase = Phase(ds.currentPhase_int);
        uint256 inputAccumulationStart = ds.inputAccumulationStart;
        uint256 inputDuration = ds.inputDuration;

        if (
            currentPhase == Phase.InputAccumulation &&
            block.timestamp > inputAccumulationStart + inputDuration
        ) {
            currentPhase = Phase.AwaitingConsensus;
            ds.currentPhase_int = uint32(Phase.AwaitingConsensus);
            emit PhaseChange(Phase.AwaitingConsensus);

            // warns input of new epoch
            LibInput.onNewInputAccumulation();
            // update timestamp of sealing epoch proposal
            ds.sealingEpochTimestamp = uint32(block.timestamp);
        }

        require(
            currentPhase == Phase.AwaitingConsensus,
            "Phase != AwaitingConsensus"
        );
        (result, claims, claimers) = LibValidatorManager.onClaim(
            payable(msg.sender),
            _epochHash
        );

        // emit the claim event before processing it
        // so if the epoch is finalized in this claim (consensus)
        // the number of final epochs doesnt gets contaminated
        emit Claim(
            LibOutput.getNumberOfFinalizedEpochs(),
            msg.sender,
            _epochHash
        );

        LibRollups.resolveValidatorResult(result, claims, claimers);
    }

    /// @notice finalize epoch after timeout
    /// @dev can only be called if challenge period is over
    function finalizeEpoch() public override {
        LibRollups.DiamondStorage storage ds = LibRollups.diamondStorage();

        Phase currentPhase = Phase(ds.currentPhase_int);
        require(
            currentPhase == Phase.AwaitingConsensus,
            "Phase != Awaiting Consensus"
        );

        uint256 sealingEpochTimestamp = ds.sealingEpochTimestamp;
        uint256 challengePeriod = ds.challengePeriod;
        require(
            block.timestamp > sealingEpochTimestamp + challengePeriod,
            "Challenge period not over"
        );

        require(
            LibValidatorManager.getCurrentClaim() != bytes32(0),
            "No Claim to be finalized"
        );

        LibRollups.startNewEpoch();
    }

    /// @notice returns index of current (accumulating) epoch
    /// @return index of current epoch
    /// @dev if phase is input accumulation, then the epoch number is length
    //       of finalized epochs array, else there are two non finalized epochs,
    //       one awaiting consensus/dispute and another accumulating input
    function getCurrentEpoch() public view override returns (uint256) {
        return LibRollups.getCurrentEpoch();
    }
}