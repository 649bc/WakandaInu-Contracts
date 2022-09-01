pragma solidity ^0.6.0;

import "@openzeppelin/token/ERC20/ERC20.sol";

contract MOCKWAKANDA is ERC20("WAKANDA", "WKD") {
    constructor() public {
        _mint(0x57FF251Ac638D3d03AB7550ADFD3E166C2E7aDB6, 10000e18);
    }
}
