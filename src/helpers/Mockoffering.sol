pragma solidity ^0.6.0;
import "@openzeppelin/token/ERC20/ERC20.sol";

contract MOCKOFF is ERC20("OFFERING", "OFF") {
    constructor() public {
        _mint(msg.sender, 1000000e18);
    }

    function mintToUser() public {
        _mint(msg.sender, 1000000e9);
    }

    function mintTo(address user) public {
        _mint(user, 1000000e18);
    }
}
