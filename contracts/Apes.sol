// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Apes is Ownable, ReentrancyGuard, ERC721 {
    using Strings for uint256;

    // variables for mint
    bool public isMintOn = false;

    bool public saleHasBeenStarted = false;

    uint256 public constant MAX_MINTABLE_AT_ONCE = 50;

    uint256[10000] private _availableTokens;
    uint256 private _numAvailableTokens = 10000;
    uint256 private _lastTokenIdMintedInInitialSet = 10000;
   
    // variables for market
    struct Offer {
        bool isForSale;
        uint tokenId;
        address seller;
        uint minValue;          // in ether
        address onlySellTo;     // specify to sell only to a specific person
    }

    struct Bid {
        bool hasBid;
        uint tokenId;
        address bidder;
        uint value;
    }

    // A record of apes that are offered for sale at a specific minimum value, and perhaps to a specific person
    mapping (uint => Offer) public apesOfferedForSale;

    // A record of the highest ape bid
    mapping (uint => Bid) public apesBids;

    mapping (address => uint) public pendingWithdrawals;

    event ApesOffered(uint indexed tokenId, uint minValue, address indexed toAddress);
    event ApesBidEntered(uint indexed tokenId, uint value, address indexed fromAddress);
    event ApesBidWithdrawn(uint indexed tokenId, uint value, address indexed fromAddress);
    event ApesBought(uint indexed tokenId, uint value, address indexed fromAddress, address indexed toAddress);
    event ApesNoLongerForSale(uint indexed tokenId);


    constructor() ERC721("0xApes", "0xApes") {}
    
    function numTotalApes() public view virtual returns (uint256) {
        return 10000;
    }

    function mint(uint256 _numToMint) public payable nonReentrant() {
        require(isMintOn, "Sale hasn't started.");
        require(
            _numToMint <= _numAvailableTokens,
            "There aren't this many Apes left."
        );
        uint256 costForMintingApes = getCostForMintingApes(_numToMint);
        require(
            msg.value >= costForMintingApes,
            "Too little sent, please send more eth."
        );
        if (msg.value > costForMintingApes) {
            require(_safeTransferETH(msg.sender, msg.value - costForMintingApes));
        }

        // transfer cost for mint to owner address
        require(_safeTransferETH(owner(), costForMintingApes), "failed to transfer minting cost");

        _mint(_numToMint);
    }

    // internal minting function
    function _mint(uint256 _numToMint) internal {
        require(_numToMint <= MAX_MINTABLE_AT_ONCE, "Minting too many at once.");

        for (uint256 i = 0; i < _numToMint; i++) {
            uint256 newTokenId = useRandomAvailableToken(_numToMint, i);
            _safeMint(msg.sender, newTokenId + 10000);
        }
    }

    function useRandomAvailableToken(uint256 _numToFetch, uint256 _i)
        internal
        returns (uint256)
    {
        uint256 randomNum =
        uint256(
            keccak256(
            abi.encode(
                msg.sender,
                tx.gasprice,
                block.number,
                block.timestamp,
                blockhash(block.number - 1),
                _numToFetch,
                _i
            )
            )
        );
        uint256 randomIndex = randomNum % _numAvailableTokens;
        return useAvailableTokenAtIndex(randomIndex);
    }

    function useAvailableTokenAtIndex(uint256 indexToUse)
        internal
        returns (uint256)
    {
        uint256 valAtIndex = _availableTokens[indexToUse];
        uint256 result;
        if (valAtIndex == 0) {
            // This means the index itself is still an available token
            result = indexToUse;
        } else {
            // This means the index itself is not an available token, but the val at that index is.
            result = valAtIndex;
        }

        uint256 lastIndex = _numAvailableTokens - 1;
        if (indexToUse != lastIndex) {
            // Replace the value at indexToUse, now that it's been used.
            // Replace it with the data from the last index in the array, since we are going to decrease the array size afterwards.
            uint256 lastValInArray = _availableTokens[lastIndex];
            if (lastValInArray == 0) {
                // This means the index itself is still an available token
                _availableTokens[indexToUse] = lastIndex;
            } else {
                // This means the index itself is not an available token, but the val at that index is.
                _availableTokens[indexToUse] = lastValInArray;
            }
        }

        _numAvailableTokens--;
        return result;
    }

    function getCostForMintingApes(uint256 _numToMint)
        public
        view
        returns (uint256)
    {
        require(
            _numToMint <= _numAvailableTokens,
            "There aren't this many Apes left."
        );
        return 0.05 ether * _numToMint;
    }

    /*
    * Dev stuff.
    */

    // metadata URI
    string private _baseTokenURI;

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        string memory base = _baseURI();
        string memory _tokenURI = Strings.toString(_tokenId);

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }

        return string(abi.encodePacked(base, _tokenURI));
    }

    /*
    * Owner stuff
    */

    function startMinting() public onlyOwner {
        isMintOn = true;
        saleHasBeenStarted = true;
    }

    function endMinting() public onlyOwner {
        isMintOn = false;
    }

    // for seeding the v2 contract with v1 state
    function seedInitialContractState(
        address[] memory tokenOwners,
        uint256[] memory tokens
    ) public onlyOwner {
        require(
            !saleHasBeenStarted,
            "cannot initial phunk mint if sale has started"
        );
        require(
            tokenOwners.length == tokens.length,
            "tokenOwners does not match tokens length"
        );

        uint256 lastTokenIdMintedInInitialSetCopy = _lastTokenIdMintedInInitialSet;
        for (uint256 i = 0; i < tokenOwners.length; i++) {
            uint256 token = tokens[i];
            require(
                lastTokenIdMintedInInitialSetCopy > token,
                "initial phunk mints must be in decreasing order for our availableToken index to work"
            );
            lastTokenIdMintedInInitialSetCopy = token;

            useAvailableTokenAtIndex(token);
            _safeMint(tokenOwners[i], token + 10000);
        }

        _lastTokenIdMintedInInitialSet = lastTokenIdMintedInInitialSetCopy;
    }

    // URIs
    function setBaseURI(string memory baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    /***********************************************************************************************************************
     *   Ape Market
     * 
    ***********************************************************************************************************************/

    function apesNoLongerForSale(uint tokenId) public onlyApesOwner(tokenId) {
        apesOfferedForSale[tokenId] = Offer(false, tokenId, msg.sender, 0, address(0x0));
        emit ApesNoLongerForSale(tokenId);
    }

    function offerApesForSale(uint tokenId, uint minSalePriceInWei) public onlyApesOwner(tokenId) {
        apesOfferedForSale[tokenId] = Offer(true, tokenId, msg.sender, minSalePriceInWei, address(0x0));
        emit ApesOffered(tokenId, minSalePriceInWei, address(0x0));
    }

    function offerApesForSaleToAddress(uint tokenId, uint minSalePriceInWei, address toAddress) public onlyApesOwner(tokenId) {
        apesOfferedForSale[tokenId] = Offer(true, tokenId, msg.sender, minSalePriceInWei, toAddress);
        emit ApesOffered(tokenId, minSalePriceInWei, toAddress);
    }

    function buyApes(uint tokenId) public payable nonReentrant() {
        Offer memory offer = apesOfferedForSale[tokenId];
        require (offer.isForSale, "this token is not for sale");                // ape not actually for sale
        require (offer.onlySellTo == address(0x0) || offer.onlySellTo == msg.sender, "not available for you");  // ape not supposed to be sold to this user
        require (msg.value >= offer.minValue, "invalid eth value");      // Didn't send enough ETH
        require (offer.seller == ownerOf(tokenId), "seller is not owner"); // Seller no longer owner of ape

        address seller = offer.seller;

        _safeTransfer(seller, msg.sender, tokenId, "buying apes");

        apesNoLongerForSale(tokenId);
        pendingWithdrawals[seller] += msg.value;
        emit ApesBought(tokenId, msg.value, seller, msg.sender);

        // Check for the case where there is a bid from the new owner and refund it.
        // Any other bid can stay in place.
        Bid memory bid = apesBids[tokenId];
        if (bid.bidder == msg.sender) {
            // Kill bid and refund value
            pendingWithdrawals[msg.sender] += bid.value;
            apesBids[tokenId] = Bid(false, tokenId, address(0x0), 0);
        }
    }

    function withdraw() public nonReentrant() {
        uint amount = pendingWithdrawals[msg.sender];
        // Remember to zero the pending refund before
        // sending to prevent re-entrancy attacks
        pendingWithdrawals[msg.sender] = 0;
        _safeTransferETH(msg.sender, amount);
    }

    function enterBidForApes(uint tokenId) public payable {
        require(ownerOf(tokenId) != address(0x0), "not minted token");
        require(ownerOf(tokenId) != address(msg.sender), "impossible for owned token");
        require (msg.value > 0, "not enough eth");
        
        Bid memory existing = apesBids[tokenId];
        require(msg.value > existing.value, "low than previous");
    
        if (existing.value > 0) {
            // Refund the failing bid
            pendingWithdrawals[existing.bidder] += existing.value;
        }
        apesBids[tokenId] = Bid(true, tokenId, msg.sender, msg.value);
        emit ApesBidEntered(tokenId, msg.value, msg.sender);
    }

    function acceptBidForApes(uint tokenId, uint minPrice) public onlyApesOwner(tokenId) {
        address seller = msg.sender;
        Bid memory bid = apesBids[tokenId];
        require(bid.value > 0 && bid.value > minPrice, "invalid bid price");
        
        _safeTransfer(seller, bid.bidder, tokenId, "win");
        
        apesOfferedForSale[tokenId] = Offer(false, tokenId, bid.bidder, 0, address(0x0));
        uint amount = bid.value;
        apesBids[tokenId] = Bid(false, tokenId, address(0x0), 0);
        pendingWithdrawals[seller] += amount;
        emit ApesBought(tokenId, bid.value, seller, bid.bidder);
    }

    function withdrawBidForApes(uint tokenId) public nonReentrant() {
        require(ownerOf(tokenId) != address(0x0), "not minted token");
        require(ownerOf(tokenId) != address(msg.sender), "impossible for owned token");

        Bid memory bid = apesBids[tokenId];
        require (bid.bidder == msg.sender, "not bidder");

        emit ApesBidWithdrawn(tokenId, bid.value, msg.sender);
        uint amount = bid.value;
        apesBids[tokenId] = Bid(false, tokenId, address(0x0), 0);
        // Refund the bid money
        require(_safeTransferETH(msg.sender, amount), "failed to refund");
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721) {
        super._beforeTokenTransfer(from, to, tokenId);

        if (apesOfferedForSale[tokenId].isForSale) {
            apesNoLongerForSale(tokenId);
        }
        
        // Check for the case where there is a bid from the new owner and refund it.
        // Any other bid can stay in place.
        Bid memory bid = apesBids[tokenId];
        if (bid.bidder == to) {
            // Kill bid and refund value
            pendingWithdrawals[to] += bid.value;
            apesBids[tokenId] = Bid(false, tokenId, address(0x0), 0);
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    receive() external payable {}

    function _safeTransferETH(address to, uint256 value) internal returns(bool) {
		(bool success, ) = to.call{value: value}(new bytes(0));
		return success;
    }

    modifier onlyApesOwner(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender, "only for apes owner");
        _;
    }
}