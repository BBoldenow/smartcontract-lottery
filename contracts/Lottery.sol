// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.6/vendor/SafeMathChainlink.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";

contract Lottery is VRFConsumerBase, Ownable {
    address payable[] public players;
    address payable public RecentWinner;
    uint256 public usdEntryFee;
    uint256 public Fee;
    bytes32 public KeyHash;
    AggregatorV3Interface internal ethUsdPriceFeed;

    enum LOTTERY_STATE {
        OPEN,
        CLOSED,
        CALCULATING_WINNER
    }

    LOTTERY_STATE public lottery_state;
    event RequestedRandomness(bytes32 requestId);

    constructor(
        address priceFeed,
        address vrfCoordinator,
        address link,
        uint256 fee,
        bytes32 keyHash
    ) public VRFConsumerBase(vrfCoordinator, link) {
        usdEntryFee = 50 * (10**18);
        ethUsdPriceFeed = AggregatorV3Interface(priceFeed);
        lottery_state = LOTTERY_STATE.CLOSED;
        Fee = fee;
        KeyHash = keyHash;
    }

    function enter() public payable {
        // $50 minimum
        require(
            lottery_state == LOTTERY_STATE.OPEN,
            "The lottery is not open yet."
        );
        require(msg.value >= getEntranceFee(), "Not enough ETH!");
        players.push(msg.sender);
    }

    function getEntranceFee() public view returns (uint256) {
        (, int256 price, , , ) = ethUsdPriceFeed.latestRoundData();
        uint256 adjustedPrice = uint256(price) * 10**10; // 18 decimals
        // $50, $2,000 / ETH
        // 50/2,000
        // 50 * 100000 / 2000
        uint256 costToEnter = (usdEntryFee * 10**18) / adjustedPrice;
        return costToEnter;
    }

    function startLottery() public onlyOwner {
        require(
            lottery_state == LOTTERY_STATE.CLOSED,
            "Can't start a new lottery yet!"
        );

        lottery_state = LOTTERY_STATE.OPEN;
    }

    function endLottery() public onlyOwner {
        lottery_state = LOTTERY_STATE.CALCULATING_WINNER;

        bytes32 requestId = requestRandomness(KeyHash, Fee);
        emit RequestedRandomness(requestId);
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        require(
            lottery_state == LOTTERY_STATE.CALCULATING_WINNER,
            "The lottery isn't over yet!"
        );

        require(randomness > 0, "Random number not found");

        uint256 indexOfWinner = randomness % players.length;
        RecentWinner = players[indexOfWinner];
        RecentWinner.transfer(address(this).balance);

        // Reset
        players = new address payable[](0);
        lottery_state = LOTTERY_STATE.CLOSED;
    }

    // This is a bad way to get a random number
    // never deploy something like the below!
    // function endLottery() public onlyOwner {
    //     uint256(
    //         keccack256(
    //             abi.encodePacked(
    //                 nonce, // predictable
    //                 msg.sender, // predictable
    //                 block.difficulty, // can actually be manipulated by the miners
    //                 block.timestamp // predictable
    //             )
    //         )
    //     ) % players.length;
    // }
}
