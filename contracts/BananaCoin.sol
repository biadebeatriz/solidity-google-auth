// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BananaCoin is ERC20, Ownable {
    constructor() ERC20("BananaCoin", "BT") {
        _mint(msg.sender, 10000 * 10**uint256(18));
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}