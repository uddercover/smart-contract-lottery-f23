//SPDX-License-Identifier:MIT
pragma solidity ^0.8.1;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DeployRaffle} from "../../scripts/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../scripts/HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {Vm} from "forge-std/Vm.sol";

contract RaffleTest is Test {
    /**Events */
    event EnteredRaffle(address indexed entrant);

    Raffle raffle;
    HelperConfig helperConfig;
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    uint256 deployerKey;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipTest() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        //Contents of helperConfig.activeNetworkConfig split to prevent error: stack too deep
        (entranceFee, interval, vrfCoordinator, gasLane, , , , ) = helperConfig
            .activeNetworkConfig();
        (
            ,
            ,
            ,
            ,
            subscriptionId,
            callbackGasLimit,
            link,
            deployerKey
        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /////////////////////
    // enterRaffle     //
    /////////////////////
    function testRaffleMustBeOpenToEnter() public raffleEnteredAndTimePassed {
        //Arrange
        raffle.performUpkeep("");

        //Act/Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        raffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();
    }

    function testPeopleMustPayEnoughMoneyToEnterRaffle() public {
        //Arrange
        vm.prank(PLAYER);
        //Act/Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public {
        //Arrange
        vm.prank(PLAYER);
        //Act
        raffle.enterRaffle{value: entranceFee}();
        address entrantAddress = raffle.getEntrant(0);
        //assert
        assert(entrantAddress == PLAYER);
    }

    function testEventIsEmittedAfterRaffleIsEntered() public {
        //arrange
        vm.prank(PLAYER);
        //act/assert
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    ///////////////////
    ////checkUpkeep////
    ///////////////////

    function testCheckUpkeepReturnsFalseIfRaffleIsNotOpen()
        public
        raffleEnteredAndTimePassed
    {
        //Arrange
        raffle.performUpkeep("");
        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        //Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasNotPassed() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfItsBalanceIsZero() public {
        //Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenAllParametersAreGood()
        public
        raffleEnteredAndTimePassed
    {
        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //Assert
        assert(upkeepNeeded);
    }

    //////////////////
    ///performUpkeep//
    //////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepReturnsTrue()
        public
        raffleEnteredAndTimePassed
    {
        //Act/Assert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepReturnsFalse() public {
        //Arrange
        uint256 currentBalance = address(raffle).balance; //balance is subject to change so should not be set to zero e.g sending eth directly to the contract
        uint256 numPlayers = 0; // numPlayers and raffleState are always reset at the end so they can be set to zero
        uint256 raffleState = 0;

        console.log(address(raffle).balance); //79228162514264337593543950335
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestedWinner()
        public
        raffleEnteredAndTimePassed
    {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();

        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    ////////////////////////////
    /////fulfillRandomWords////
    //////////////////////////
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public skipTest raffleEnteredAndTimePassed {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomNumberPicksAWinnerResetsRaffleStateAndSendsThePrizeToTheWinner()
        public
        skipTest
        raffleEnteredAndTimePassed
    {
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for (uint256 i = 1; i < additionalEntrants + startingIndex; i++) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 prize = raffle.getNumberOfEntrants() * entranceFee;
        uint256 previousTimeStamp = raffle.getLastTimeStamp();
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        vm.recordLogs();
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );
        Vm.Log[] memory fulfillRandomWordsEntries = vm.getRecordedLogs();
        bytes32 winner = fulfillRandomWordsEntries[0].topics[1];

        assert(raffle.getWinner() != address(0));
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getNumberOfEntrants() == 0);
        assert(raffle.getLastTimeStamp() > previousTimeStamp);
        assert(uint256(winner) > 0);
        assert(
            raffle.getWinner().balance >=
                prize + STARTING_USER_BALANCE - entranceFee
        );
    }
}
