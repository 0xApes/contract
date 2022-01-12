// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Apes is Ownable, ERC721Enumerable, ReentrancyGuard {
    using Strings for uint256;

    // variables for mint
    bool public isMintOn = false;

    bool public saleHasBeenStarted = false;

    uint256 public constant MAX_MINTABLE_AT_ONCE = 50;

    uint256[10000] private _availableTokens;
    uint256 private _numAvailableTokens = 10000;
    uint256 private _numFreeRollsGiven = 0;

    mapping(address => uint256) public freeRollApes;

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

    // A record of punks that are offered for sale at a specific minimum value, and perhaps to a specific person
    mapping (uint => Offer) public punksOfferedForSale;

    // A record of the highest punk bid
    mapping (uint => Bid) public punkBids;

    mapping (address => uint) public pendingWithdrawals;

    event PunkOffered(uint indexed tokenId, uint minValue, address indexed toAddress);
    event PunkBidEntered(uint indexed tokenId, uint value, address indexed fromAddress);
    event PunkBidWithdrawn(uint indexed tokenId, uint value, address indexed fromAddress);
    event PunkBought(uint indexed tokenId, uint value, address indexed fromAddress, address indexed toAddress);
    event PunkNoLongerForSale(uint indexed tokenId);


    constructor() ERC721("0xApes", "0xApe") {}
    
    function numTotalApes() public view virtual returns (uint256) {
        return 10000;
    }
        
    function freeRollMint() public nonReentrant() {
        uint256 toMint = freeRollApes[msg.sender];
        freeRollApes[msg.sender] = 0;
        uint256 remaining = numTotalApes() - totalSupply();
        if (toMint > remaining) {
            toMint = remaining;
        }
        _mint(toMint);
    }

    function getNumFreeRollApes(address owner) public view returns (uint256) {
        return freeRollApes[owner];
    }

    function mint(uint256 _numToMint) public payable nonReentrant() {
        require(isMintOn, "Sale hasn't started.");
        uint256 totalSupply = totalSupply();
        require(
            totalSupply + _numToMint <= numTotalApes(),
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

        uint256 updatedNumAvailableTokens = _numAvailableTokens;
        for (uint256 i = 0; i < _numToMint; i++) {
            uint256 newTokenId = useRandomAvailableToken(_numToMint, i);
            _safeMint(msg.sender, newTokenId + 10000);
            updatedNumAvailableTokens--;
        }
        _numAvailableTokens = updatedNumAvailableTokens;
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
            totalSupply() + _numToMint <= numTotalApes(),
            "There aren't this many Apes left."
        );
        return 0.05 ether * _numToMint;
    }

    function getApesBelongingToOwner(address _owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 numApes = balanceOf(_owner);
        if (numApes == 0) {
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](numApes);
            for (uint256 i = 0; i < numApes; i++) {
                result[i] = tokenOfOwnerByIndex(_owner, i);
            }
            return result;
        }
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

    // contract metadata URI for opensea
    string public contractURI;

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

    function giveFreeRoll(address receiver) public onlyOwner {
        // max number of free mints we can give to the community for promotions/marketing
        require(_numFreeRollsGiven < 200, "already given max number of free rolls");
        uint256 freeRolls = freeRollApes[receiver];
        freeRollApes[receiver] = freeRolls + 1;
        _numFreeRollsGiven = _numFreeRollsGiven + 1;
    }

    // for handing out free rolls to v1 phunk owners
    function seedFreeRolls(
        address[] memory tokenOwners,
        uint256[] memory numOfFreeRolls
    ) public onlyOwner {
        require(
            !saleHasBeenStarted,
            "cannot seed free rolls after sale has started"
        );
        require(
            tokenOwners.length == numOfFreeRolls.length,
            "tokenOwners does not match numOfFreeRolls length"
        );

        // light check to make sure the proper values are being passed
        require(numOfFreeRolls[0] <= 3, "cannot give more than 3 free rolls");

        for (uint256 i = 0; i < tokenOwners.length; i++) {
            freeRollApes[tokenOwners[i]] = numOfFreeRolls[i];
        }
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

    function setContractURI(string memory _contractURI) external onlyOwner {
        contractURI = _contractURI;
    }

    /***********************************************************************************************************************
     *   Punk Market
     * 
    ***********************************************************************************************************************/

    function punkNoLongerForSale(uint tokenId) public onlyPunkOwner(tokenId) {
        punksOfferedForSale[tokenId] = Offer(false, tokenId, msg.sender, 0, address(0x0));
        emit PunkNoLongerForSale(tokenId);
    }

    function offerPunkForSale(uint tokenId, uint minSalePriceInWei) public onlyPunkOwner(tokenId) {
        punksOfferedForSale[tokenId] = Offer(true, tokenId, msg.sender, minSalePriceInWei, address(0x0));
        emit PunkOffered(tokenId, minSalePriceInWei, address(0x0));
    }

    function offerPunkForSaleToAddress(uint tokenId, uint minSalePriceInWei, address toAddress) public onlyPunkOwner(tokenId) {
        punksOfferedForSale[tokenId] = Offer(true, tokenId, msg.sender, minSalePriceInWei, toAddress);
        emit PunkOffered(tokenId, minSalePriceInWei, toAddress);
    }

    function buyPunk(uint tokenId) public payable nonReentrant() {
        Offer memory offer = punksOfferedForSale[tokenId];
        require (offer.isForSale, "this token is not for sale");                // punk not actually for sale
        require (offer.onlySellTo == address(0x0) || offer.onlySellTo == msg.sender, "not available for you");  // punk not supposed to be sold to this user
        require (msg.value >= offer.minValue, "invalid eth value");      // Didn't send enough ETH
        require (offer.seller == ownerOf(tokenId), "seller is not owner"); // Seller no longer owner of punk

        address seller = offer.seller;

        _safeTransfer(seller, msg.sender, tokenId, "buying punk");

        punkNoLongerForSale(tokenId);
        pendingWithdrawals[seller] += msg.value;
        emit PunkBought(tokenId, msg.value, seller, msg.sender);

        // Check for the case where there is a bid from the new owner and refund it.
        // Any other bid can stay in place.
        Bid memory bid = punkBids[tokenId];
        if (bid.bidder == msg.sender) {
            // Kill bid and refund value
            pendingWithdrawals[msg.sender] += bid.value;
            punkBids[tokenId] = Bid(false, tokenId, address(0x0), 0);
        }
    }

    function withdraw() public nonReentrant() {
        uint amount = pendingWithdrawals[msg.sender];
        // Remember to zero the pending refund before
        // sending to prevent re-entrancy attacks
        pendingWithdrawals[msg.sender] = 0;
        _safeTransferETH(msg.sender, amount);
    }

    function enterBidForPunk(uint tokenId) public payable {
        require(ownerOf(tokenId) != address(0x0), "not minted token");
        require(ownerOf(tokenId) != address(msg.sender), "impossible for owned token");
        require (msg.value > 0, "not enough eth");
        
        Bid memory existing = punkBids[tokenId];
        require(msg.value > existing.value, "low than previous");
    
        if (existing.value > 0) {
            // Refund the failing bid
            pendingWithdrawals[existing.bidder] += existing.value;
        }
        punkBids[tokenId] = Bid(true, tokenId, msg.sender, msg.value);
        emit PunkBidEntered(tokenId, msg.value, msg.sender);
    }

    function acceptBidForPunk(uint tokenId, uint minPrice) public onlyPunkOwner(tokenId) {
        address seller = msg.sender;
        Bid memory bid = punkBids[tokenId];
        require(bid.value > 0 && bid.value > minPrice, "invalid bid price");
        
        _safeTransfer(seller, bid.bidder, tokenId, "win");
        
        punksOfferedForSale[tokenId] = Offer(false, tokenId, bid.bidder, 0, address(0x0));
        uint amount = bid.value;
        punkBids[tokenId] = Bid(false, tokenId, address(0x0), 0);
        pendingWithdrawals[seller] += amount;
        emit PunkBought(tokenId, bid.value, seller, bid.bidder);
    }

    function withdrawBidForPunk(uint tokenId) public nonReentrant() {
        require(ownerOf(tokenId) != address(0x0), "not minted token");
        require(ownerOf(tokenId) != address(msg.sender), "impossible for owned token");

        Bid memory bid = punkBids[tokenId];
        require (bid.bidder == msg.sender, "not bidder");

        emit PunkBidWithdrawn(tokenId, bid.value, msg.sender);
        uint amount = bid.value;
        punkBids[tokenId] = Bid(false, tokenId, address(0x0), 0);
        // Refund the bid money
        require(_safeTransferETH(msg.sender, amount), "failed to refund");
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);

        if (punksOfferedForSale[tokenId].isForSale) {
            punkNoLongerForSale(tokenId);
        }
        
        // Check for the case where there is a bid from the new owner and refund it.
        // Any other bid can stay in place.
        Bid memory bid = punkBids[tokenId];
        if (bid.bidder == to) {
            // Kill bid and refund value
            pendingWithdrawals[to] += bid.value;
            punkBids[tokenId] = Bid(false, tokenId, address(0x0), 0);
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    receive() external payable {}

    function _safeTransferETH(address to, uint256 value) internal returns(bool) {
		(bool success, ) = to.call{value: value}(new bytes(0));
		return success;
    }

    modifier onlyPunkOwner(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender, "only for punk owner");
        _;
    }
}