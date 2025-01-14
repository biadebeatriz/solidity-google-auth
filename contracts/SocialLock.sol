pragma solidity ^0.5.0;

/// @title SocialLock - SocialLock contract to lock funds in a smart contract and release them when a Google JWT is provided
/// @dev This contract is intended to be used with a Google OAuth2 Web App. It locks funds in a smart contract and releases them when a Google JWT is provided.
/// @author Lucas Henning - <lucas@suku.world>
/// based on https://github.com/OpenZeppelin/solidity-jwt

import "./IERC20.sol";
import "./lib/Base64.sol";
import "./lib/JsmnSolLib.sol";
import "./lib/SolRsaVerify.sol";
import "./lib/Strings.sol";
import "./JWT.sol";
import "./JWKSOracle.sol";

import "hardhat/console.sol";

interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}
contract SocialLock {

  using Base64 for string;
  using StringUtils for *;
  using SolRsaVerify for *;
  using JsmnSolLib for string;

  /**
  * This mapping stores the Google email address and maps it to a balance
  * @dev Emails need to be keccak256 hashed before being used as a key
  */
  mapping (bytes32 => uint) public balances;

  /**
  * @dev Same as above for tokens. UserEmailHash -> TokenAddress -> Balance
  */
  mapping (bytes32 => mapping (address => uint)) public tokenBalances;

  string public audience;
  JWKSOracle public jwksOracle;
  
  /**
  * @dev creates a SocialLock contract with a given audience (= Google OAuth2 Web App) and JWKS key oracle (RSA public keys)
  * @param aud The audience of the Google OAuth2 Web App, this is the client ID of the Google OAuth2 Web App, e.g. 1234567890-1234567890.apps.googleusercontent.com
  * @param _jwksOracle The JWKS key oracle, this is a contract that stores the RSA public keys of the Google OAuth2 Web App
  */
  constructor(string memory aud, JWKSOracle _jwksOracle) public payable {
    audience = aud;
    jwksOracle = _jwksOracle;
  }

  /**
  * Deposit ETH into the contract for a given email address
  * @param email The google email address of the user (needs to be keccak256 hashed before being used as a key)
  */
  function deposit(bytes32 email) public payable {
    balances[email] += msg.value;
  }

  function withdraw(string memory headerJson, string memory payloadJson, bytes memory signature, uint amount) public {
    // validate JWT
    string memory email = validateJwt(headerJson, payloadJson, signature);
    bytes32 emailHash = keccak256(abi.encodePacked(email));
    
    // balance check
    // this uses the email address from the Google JWT to check if there is a balance for this email
    require(balances[emailHash] > 0, "No balance for this email");
    require(balances[emailHash] >= amount, "Not enough balance for this email");

    // transfer
    balances[emailHash] -= amount;
    msg.sender.transfer(amount);
  }

  /**
  * Deposit ERC20 tokens into the contract
  * @param email The google email address of the user (needs to be keccak256 hashed before being used as a key)
  * @param token The ERC20 token address
  * @param amount The amount of tokens to deposit
  */
  function depositToken(bytes32 email, IERC20 token, uint amount) public {
    token.transferFrom(msg.sender, address(this), amount);
    tokenBalances[email][address(token)] += amount;
  }

  function withdrawToken(string memory headerJson, string memory payloadJson, bytes memory signature, IERC20 token, uint amount) public {
    // validate JWT
    string memory email = validateJwt(headerJson, payloadJson, signature);
    bytes32 emailHash = keccak256(abi.encodePacked(email));

    // balance check
    require(tokenBalances[emailHash][address(token)] > 0, "No balance for this email");
    require(tokenBalances[emailHash][address(token)] >= amount, "Not enough balance for this email");

    // transfer
    tokenBalances[emailHash][address(token)] -= amount;
    token.transfer(msg.sender, amount);
  }

  function validateJwt(string memory headerJson, string memory payloadJson, bytes memory signature) internal returns (string memory) {
    string memory headerBase64 = headerJson.encode();
    string memory payloadBase64 = payloadJson.encode();
    StringUtils.slice[] memory slices = new StringUtils.slice[](2);
    slices[0] = headerBase64.toSlice();
    slices[1] = payloadBase64.toSlice();
    string memory message = ".".toSlice().join(slices);
    string memory kid = parseHeader(headerJson);
    bytes memory exponent = getRsaExponent(kid);
    bytes memory modulus = getRsaModulus(kid);

    // signature check
    require(message.pkcs1Sha256VerifyStr(signature, exponent, modulus) == 0, "RSA signature check failed");

    (string memory aud, string memory nonce, string memory sub, string memory email) = parseToken(payloadJson);
    
    // audience check, this is the Google OAuth2 Web App clientID
    require(aud.strCompare(audience) == 0, "Audience does not match");

    // nonce check 
    // the nonce is the destination address that will receive the funds and also the address triggering this transaction (msg.sender)
    // we're validating if Google JWT includes the nonce (msg.sender) in the payload
    string memory senderBase64 = string(abi.encodePacked(msg.sender)).encode();
    console.log('senderBase64', senderBase64);
    console.log('nonce', nonce);
    require(senderBase64.strCompare(nonce) == 0, "Sender does not match nonce");

    return email;
  }

  function parseHeader(string memory json) internal pure returns (string memory kid) {
    (uint exitCode, JsmnSolLib.Token[] memory tokens, uint ntokens) = json.parse(20);
    require(exitCode == 0, "JSON parse failed");
    
    require(tokens[0].jsmnType == JsmnSolLib.JsmnType.OBJECT, "Expected JWT to be an object");
    uint i = 1;
    while (i < ntokens) {
      require(tokens[i].jsmnType == JsmnSolLib.JsmnType.STRING, "Expected JWT to contain only string keys");
      string memory key = json.getBytes(tokens[i].start, tokens[i].end);
      if (key.strCompare("kid") == 0) {
        require(tokens[i+1].jsmnType == JsmnSolLib.JsmnType.STRING, "Expected kid to be a string");
        return json.getBytes(tokens[i+1].start, tokens[i+1].end);
      }
      i += 2;
    }
  }

  function parseToken(string memory json) internal pure returns (string memory aud, string memory nonce, string memory sub, string memory email) {
    (uint exitCode, JsmnSolLib.Token[] memory tokens, uint ntokens) = json.parse(40);
    require(exitCode == 0, "JSON parse failed");
    
    require(tokens[0].jsmnType == JsmnSolLib.JsmnType.OBJECT, "Expected JWT to be an object");
    uint i = 1;
    while (i < ntokens) {
      require(tokens[i].jsmnType == JsmnSolLib.JsmnType.STRING, "Expected JWT to contain only string keys");
      string memory key = json.getBytes(tokens[i].start, tokens[i].end);
      if (key.strCompare("sub") == 0) {
        require(tokens[i+1].jsmnType == JsmnSolLib.JsmnType.STRING, "Expected sub to be a string");
        sub = json.getBytes(tokens[i+1].start, tokens[i+1].end);
      } else if (key.strCompare("aud") == 0) {
        require(tokens[i+1].jsmnType == JsmnSolLib.JsmnType.STRING, "Expected aud to be a string");
        aud = json.getBytes(tokens[i+1].start, tokens[i+1].end);
      } else if (key.strCompare("nonce") == 0) {
        require(tokens[i+1].jsmnType == JsmnSolLib.JsmnType.STRING, "Expected nonce to be a string");
        nonce = json.getBytes(tokens[i+1].start, tokens[i+1].end);
      } else if (key.strCompare("email") == 0) {
        require(tokens[i+1].jsmnType == JsmnSolLib.JsmnType.STRING, "Expected email to be a string");
        email = json.getBytes(tokens[i+1].start, tokens[i+1].end);
      }
      i += 2;
    }
  }

  function getRsaModulus(string memory kid) internal view returns (bytes memory modulus) {
    modulus = jwksOracle.getModulus(kid);
    if (modulus.length == 0) revert("RSA Modulus not found");
  }

  function getRsaExponent(string memory) internal pure returns (bytes memory) {
    return hex"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010001";
  }

}