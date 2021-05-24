// Copyright (C) 2020 Cartesi Pte. Ltd.

// SPDX-License-Identifier: GPL-3.0-only
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.

// This program is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE. See the GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// Note: This component currently has dependencies that are licensed under the GNU
// GPL, version 3, and so you should treat this component as a whole as being under
// the GPL version 3. But all Cartesi-written code in this component is licensed
// under the Apache License, version 2, or a compatible permissive license, and can
// be used independently under the Apache v2 license. After this component is
// rewritten, the entire component will be released under the Apache v2 license.

/// @title Input Implementation
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@cartesi/util/contracts/Merkle.sol";

import "./MockInput.sol";

// TODO: this contract seems to be very unsafe, need to think about security implications
contract MockInputImpl is MockInput {

    address immutable portalContract;

    bool lock; //reentrancy lock

    InputBlob[] inputBlobBox;

    struct InputBlob {
        Operation operation;
        Transaction transaction;
        address[] senders;
        address[] receivers;
        uint256[] amounts;
        address _ERC20;
        address sender; //compare msg.sender && sender element of InputBlob in the process transaction for Transfer and Withdrawal process
    }

    //ether balance of L2 addresses
    mapping(address =>  uint) etherBalanceOf;

    //token balances of L2 addresses
    mapping(address => mapping(address => uint)) erc20BalanceOf;

    /// @notice functions modified by noReentrancy are not subject to recursion
    /// TODO: up for discussion
    modifier noReentrancy() {
        require(!lock, "reentrancy not allowed");
        lock = true;
        _;
        lock = false;
    }

    constructor(address _portalContract) {
        portalContract = _portalContract;
    }

    /// @notice add input to processed by next epoch
    ///         it essentially mimics the epoch behavior
    /// @param _input input to be understood by off-chain machine
    /// @dev off-chain code is responsible for making sure
    ///      that input size is power of 2 and multiple of 8 since
    // the off-chain machine has a 8 byte word
    function addInput(bytes calldata _input, uint _op) //?? Do we need a modifier here to ensure that only the portal contract calls it?
        public
        override
        noReentrancy()
        returns (bytes32)
    {
        require(_input.length > 0 && _input.length <= 256, "input length should be between 0 and 256");
        require((inputBlobBox.length + 1) <= 10, "input box size cannot be greater than 10");

        if(Operation(_op) == Operation.EtherOp){
            (
                Operation _operation,
                Transaction _transaction,
                address[] memory _receivers,
                uint256[] memory _amounts,
                bytes memory _data
            ) = abi.decode(_input, (Operation, Transaction, address [], uint256[], bytes));

            inputBlobBox.push(
                InputBlob(_operation, _transaction, new address[](0), _receivers, _amounts, address(0), msg.sender)
            );
        }

        if(Operation(_op) == Operation.ERC20Op){
            (
                Operation _operation,
                Transaction _transaction,
                address[] memory _senders,
                address[] memory _receivers,
                uint256[] memory _amounts,
                address _ERC20,
                bytes memory _data
            ) = abi.decode(_input, (Operation, Transaction, address [], address [], uint256 [], address, bytes));

            inputBlobBox.push(
                InputBlob(_operation, _transaction, _senders , _receivers, _amounts, _ERC20, msg.sender)
            );
        }


        if(inputBlobBox.length == 10){
            processBatchInputs();
        }
        // when input box is 10
        // process each input one after the other.
        // debit and credit based on the balance of each address
        // ensure that the sender is the portal when it's deposit
        // But for transfer and withdraws, we should check that the transaction has been sent by the holder.
        bytes memory metadata = abi.encode(msg.sender, block.timestamp);
        bytes32 inputHash = keccak256(abi.encode(keccak256(metadata), keccak256(_input)));
        return inputHash;
    }

    function processBatchInputs() private returns (bool) {
        for(uint i = 0; i < inputBlobBox.length; i++){
            InputBlob memory inputBlob = inputBlobBox[i];

            if(inputBlob.operation == Operation.EtherOp){
                if(inputBlob.transaction == Transaction.Deposit){
                    for(uint j = 0;j < inputBlob.receivers.length; j++){
                        address receiver = inputBlob.receivers[i];
                        if(inputBlob.sender == portalContract){
                            uint amount = inputBlob.amounts[i];
                            inputBlob.amounts[i] = 0;
                            etherBalanceOf[receiver] += amount;
                        }
                    }
                }

                if(inputBlob.transaction == Transaction.Transfer){

                }
            }

            if(inputBlob.operation == Operation.ERC20Op){
                if(inputBlob.transaction == Transaction.Deposit){
                    for(uint j = 0;j < inputBlob.receivers.length; j++){
                        address recipient = inputBlob.receivers[i];
                        if(inputBlob.sender == portalContract){
                            uint amount = inputBlob.amounts[i];
                            inputBlob.amounts[i] = 0;
                            erc20BalanceOf[recipient][inputBlob._ERC20] += amount;
                        }
                    }
                }

                if(inputBlob.transaction == Transaction.Transfer){

                }
            }
        }

        return true;
    }

    /// @notice get input inside inbox of currently proposed claim
    /// @param _index index of input inside that inbox
    /// @return hash of input at index _index
    /// @dev currentInputBox being zero means that the inputs for
    ///      the claimed epoch are on input box one
    function getInput(uint256 _index) public view override returns (bytes memory) {
        InputBlob memory inputBlob = inputBlobBox[_index];
        return abi.encode(inputBlob);
    }

    /// @notice get number of inputs inside inbox of currently proposed claim
    /// @return number of inputs on that input box
    /// @dev currentInputBox being zero means that the inputs for
    ///      the claimed epoch are on input box one
    function getNumberOfInputs() public view override returns (uint256) {
        return inputBlobBox.length;
    }

    /// @notice called when a new epoch begins, clears deprecated inputs
    /// @dev can only be called by DescartesV2 contract
    function onNewEpoch() public override {
        // clear input box for new inputs
        // the current input box should be accumulating inputs
        // for the new epoch already. So we clear the other one.
        delete inputBlobBox;
    }
}