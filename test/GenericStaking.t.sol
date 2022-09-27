// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;

pragma solidity ^0.6.0;
import "forge-std/Test.sol";
import "../src/farm/newGenericStake.sol";
import "../src/farm/newGenericStake.sol";
import "../src/helpers/IBEP20.sol";
import "../src/helpers/MockWKD.sol";

// import "../src/helpers/MOCKRWD.sol";

contract TestGenericStake is Test {
    GenericStakeFactory factory;
    MOCKWAKANDA stakeToken;
    // MockREWARD rewardToken;
    address genericStake;


    struct UserInfo{
        uint256 amount;
        uint256 rewardDebt;
    }

    uint constant REWARDPERBLOCK = 1543209 * 1e9;
    uint rewardPrecision = 1e6;
    uint bonusEndBlock;

    function setUp() public {
        stakeToken = new MOCKWAKANDA();
        factory = new GenericStakeFactory();

        genericStake = factory.deployPool(
            IBEP20(address(stakeToken)),
            IBEP20(address(stakeToken)),
            REWARDPERBLOCK,
            block.number,
            block.number + 5,
            0,
            msg.sender
        );
    }

   

    function testDeposit() public {
        address user1 = mkaddr("user");
        address user2 = mkaddr("user2");
        address user3 = mkaddr("user3");
        address user4 = mkaddr("user4");
        vm.deal(user1, 1 ether);
        vm.startPrank(user1);
        (stakeToken).mintToUser();
        IBEP20(address(stakeToken)).approve(genericStake, 1000000e9);
        WakandaPoolInitializable(genericStake).deposit(1000000e9);
        vm.stopPrank();

        vm.startPrank(user2);
       stakeToken.mintToUser();
        IBEP20(address(stakeToken)).approve(genericStake, 1000000e9);
        WakandaPoolInitializable(genericStake).deposit(1000000e9);
        vm.stopPrank();
        vm.startPrank(user3);
        stakeToken.mintToUser();
        IBEP20(address(stakeToken)).approve(genericStake, 1000000e9);
        WakandaPoolInitializable(genericStake).deposit(1000000e9);
        vm.stopPrank();

        vm.startPrank(user4);
       stakeToken.mintToUser();
        IBEP20(address(stakeToken)).approve(genericStake, 1000000e9);
        WakandaPoolInitializable(genericStake).deposit(1000000e9);
        vm.stopPrank();

        assertEq(stakeToken.balanceOf(address(genericStake)), 1000000e9 * 4 );

        // vm.roll(700);
        
        vm.startPrank(user1);
        vm.roll(700);
        WakandaPoolInitializable(genericStake).pendingReward(user1);
        (uint _rewardDebt, uint _amount) = WakandaPoolInitializable(genericStake).viewUserInfo(user1);

        WakandaPoolInitializable(genericStake).withdraw(1000000000000067);
    }

    function mkaddr(string memory name) public returns (address) {
        address addr = address(
            uint160(uint256(keccak256(abi.encodePacked(name))))
        );
        vm.label(addr, name);
        return addr;
    }
}
