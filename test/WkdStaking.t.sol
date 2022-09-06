// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.0;

import "forge-std/Test.sol";
import "../src/Stake/WkdStake.sol";
import "../src/helpers/SafeBEP20.sol";
import "../src/Stake/WkdMock.sol";

contract WkdPoolTest is Test {
    WkdPool wkp;
    MOCKWAKANDA mWakanda;
    address admin = mkaddr("admin");
    address treasury = mkaddr("treasury");
    address operator = mkaddr("operator");
    address user = mkaddr("user");
    

    function setUp() public {
        mWakanda = new MOCKWAKANDA();
        wkp = new WkdPool(
            IBEP20(address(mWakanda)),
            address(admin),
            address(treasury),
            address(operator)
        );

    }

    function testDeposit() public {
         vm.startPrank(user);
         vm.deal(user, 10000000e18);
        mWakanda.balanceOf(user);
        mWakanda.approve(address(wkp), 1 ether);
        wkp.deposit(0.00002 ether, 2 weeks);
        // wkp.withdrawAll();
        vm.warp(block.timestamp + 2 weeks + 1 seconds);
        // vm.withdraw()
        wkp.withdrawAll();
        vm.stopPrank();  
}

 function mkaddr(string memory name) public returns (address) {
        address addr = address(
            uint160(uint256(keccak256(abi.encodePacked(name))))
        );
        vm.label(addr, name);
        return addr;
    }
}