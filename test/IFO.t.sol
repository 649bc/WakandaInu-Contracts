// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;
import "forge-std/Test.sol";
import "../src/IFO/IFODeployer.sol";
import "../src/helpers/MockLp.sol";
import "../src/helpers/Mockoffering.sol";

contract IFOTest is Test {
    MOCKLP mLP;
    MOCKOFF mOFF;

    IFOInitializableV5 ifoPool;
    address admin = mkaddr("Admin");
    address user1 = mkaddr("user1");
    address user2 = mkaddr("User2");
    address user3 = mkaddr("User3");

    function setUp() public {
        mLP = new MOCKLP();
        mOFF = new MOCKOFF();
        ifoPool = new IFOInitializableV5();

        ifoPool.initialize(
            address(mLP),
            address(mOFF),
            100,
            200,
            200,
            admin,
            100
        );
        mOFF.mintTo(address(ifoPool));
         mLP.mintTo(address(ifoPool));
        
    }

    function testAdminActions() public {
        vm.startPrank(admin);
        ifoPool.setPool(
            100e18,
            10000e18,
            10e18,
            true,
            0,
            false,
            6,
            3,
            3 days,
            2
        );
    }
    function testPoolOperations() public {
        //  carry out operations for user1
        vm.startPrank(user1);
        mLP.mintToUser();
        mLP.balanceOf(user1);
        mLP.approve(address(ifoPool), 1000000e9);
        vm.stopPrank();
        vm.prank(user1,user1);
        
        

        // vm.roll(2);
        // ifoPool.deposit(1111);
        // vm.stopPrank();

        // // user 2

        // vm.startPrank(user2);
        // mLP.mintToUser();
        // mLP.balanceOf(user2);
        // mLP.approve(address(ifoPool), 1000000e9);

        // vm.roll(2);
        // ifoPool.deposit(1111);
        // vm.stopPrank();

        // // user 3

        // vm.startPrank(user3);
        // mLP.mintToUser();
        // mLP.balanceOf(user3);
        // mLP.approve(address(ifoPool), 1000000e9);

        // vm.roll(2);
        // ifoPool.deposit(1111);
        // vm.stopPrank();
        // //  get the number of depositors in the pool
        //  ifoPool.getAddressListLength();

        //  mLP.balanceOf(address(ifoPool));
        //  mOFF.balanceOf(address(ifoPool));
        //  ifoPool.getRefundingAmount(user1);
        //  ifoPool.getRefundingAmount(user2);
        //  ifoPool.getRefundingAmount(user3);
        //  ifoPool.getUserAllocation(user1);
        //  vm.roll(345603);
        //  vm.startPrank(user1);
        //  ifoPool.harvest();

    }


    function mkaddr(string memory name) public returns (address) {
        address addr = address(
            uint160(uint256(keccak256(abi.encodePacked(name))))
        );
        vm.label(addr, name);
        return addr;
    }
}
//
