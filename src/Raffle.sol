// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title Sample Raffle Contract
 * @author Uddercover
 * @notice This contract is for creating a sample raffle
 * @dev Uses Chainlink VRFv2
 */

import {VRFCoordinatorV2Interface} from "@chainlink/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/src/v0.8/vrf/VRFConsumerBaseV2.sol";

contract Raffle is VRFConsumerBaseV2 {
    /** Errors*/
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numEntrants,
        uint256 raffleState
    );

    /** Enum keyword-used to define various states for a particular variable*/
    enum RaffleState {
        OPEN,
        CALCULATING
    }
    /** State Variables*/
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    /** @dev Duration of raffle */
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_coordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_entrants;
    uint256 private s_lastTimestamp;
    address private s_mostRecentWinner;
    RaffleState private s_raffleState;

    /**Events */
    event EnteredRaffle(address indexed entrant);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address coordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(coordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimestamp = block.timestamp;
        i_coordinator = VRFCoordinatorV2Interface(coordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() public payable {
        /** Checks */
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        /** Effects */
        s_entrants.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
        /** Interactions */
    }

    /**
     * @dev This function is required for chainlink automation to automatically pick the winner.
     * For this to happen, the following need to be true:
     * RaffleState needs to be open; RaffleState.OPEN
     * Interval needs to have passed
     * Contract needs to have eth (and players)
     * (implicit) Contract is funded with link
     */
    function checkUpkeep(
        bytes memory /* calldata*/
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool timeHasPassed = (block.timestamp - s_lastTimestamp) > i_interval;
        bool hasBalance = address(this).balance > 0;
        bool hasEntrants = s_entrants.length > 0;

        upkeepNeeded = (isOpen && timeHasPassed && hasBalance && hasEntrants);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external returns (uint256 requestId) {
        /** Checks */
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_entrants.length,
                uint256(s_raffleState)
            );
        }
        /** Effects */
        s_raffleState = RaffleState.CALCULATING;
        /** Interactions */
        requestId = i_coordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /* _requestId */,
        uint256[] memory _randomWords
    ) internal override {
        /** Checks */
        /** Effects */
        uint256 IndexOfWinner = _randomWords[0] % s_entrants.length;
        address payable winner = s_entrants[IndexOfWinner];
        s_mostRecentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        s_entrants = new address payable[](0);
        s_lastTimestamp = block.timestamp;
        emit PickedWinner(winner);
        /** Interactions */
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter Functions*/
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getWinner() external view returns (address) {
        return s_mostRecentWinner;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getEntrant(uint256 _entrantIndex) external view returns (address) {
        return s_entrants[_entrantIndex];
    }

    function getNumberOfEntrants() external view returns (uint256) {
        return s_entrants.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimestamp;
    }
}
