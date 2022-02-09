// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract ApesMarket is ReentrancyGuard, Pausable, Ownable {

    IERC721 apesContract;     // instance of the Apes contract

    struct Offer {
        bool isForSale;
        uint id;
        address seller;
        uint minValue;          // in ether
        address onlySellTo;
    }

    struct Bid {
        uint id;
        address bidder;
        uint value;
    }

    // Admin Fee
    uint public adminPercent = 2;
    uint public adminPending;

    // A record of apess that are offered for sale at a specific minimum value, and perhaps to a specific person
    mapping (uint => Offer) public offers;

    // A record of the highest apes bid
    mapping (uint => Bid) public bids;

    event Offered(uint indexed id, uint minValue, address indexed toAddress);
    event BidEntered(uint indexed id, uint value, address indexed fromAddress);
    event BidWithdrawn(uint indexed id, uint value);
    event Bought(uint indexed id, uint value, address indexed fromAddress, address indexed toAddress, bool isInstant);
    event Cancelled(uint indexed id);

    /* Initializes contract with an instance of 0xApes contract, and sets deployer as owner */
    constructor(address initialAddress) {
        IERC721(initialAddress).balanceOf(address(this));
        apesContract = IERC721(initialAddress);
    }

    function pause() external whenNotPaused onlyOwner {
        _pause();
    }

    function unpause() external whenPaused onlyOwner {
        _unpause();
    }

    /* Returns the 0xApes contract address currently being used */
    function apessAddress() external view returns (address) {
        return address(apesContract);
    }

    /* Allows the owner of the contract to set a new 0xApes contract address */
    function setApesContract(address newAddress) external onlyOwner {
        require(newAddress != address(0x0), "zero address");
        apesContract = IERC721(newAddress);
    }

    /* Allows the owner of the contract to set a new Admin Fee Percentage */
    function setAdminPercent(uint _percent) external onlyOwner {
        require(_percent >= 0 && _percent < 50, "invalid percent");
        adminPercent = _percent;
    }

    /*Allows the owner of the contract to withdraw pending ETH */
    function withdraw() external onlyOwner nonReentrant() {
        uint amount = adminPending;
        adminPending = 0;
        _safeTransferETH(msg.sender, amount);
    }

    /* Allows the owner of a 0xApes to stop offering it for sale */
    function cancelForSale(uint id) external onlyApesOwner(id) {
        offers[id] = Offer(false, id, msg.sender, 0, address(0x0));
        emit Cancelled(id);
    }

    /* Allows a 0xApes owner to offer it for sale */
    function offerForSale(uint id, uint minSalePrice) external onlyApesOwner(id) whenNotPaused {
        offers[id] = Offer(true, id, msg.sender, minSalePrice, address(0x0));
        emit Offered(id, minSalePrice, address(0x0));
    }

    /* Allows a 0xApes owner to offer it for sale to a specific address */
    function offerForSaleToAddress(uint id, uint minSalePrice, address toAddress) external onlyApesOwner(id) whenNotPaused {
        offers[id] = Offer(true, id, msg.sender, minSalePrice, toAddress);
        emit Offered(id, minSalePrice, toAddress);
    }
    

    /* Allows users to buy a 0xApes offered for sale */
    function buyApes(uint id) payable external whenNotPaused nonReentrant() {
        Offer memory offer = offers[id];
        uint amount = msg.value;
        require (offer.isForSale, 'ape is not for sale'); 
        require (offer.onlySellTo == address(0x0) || offer.onlySellTo != msg.sender, "this offer is not for you");                
        require (amount == offer.minValue, 'not enough ether'); 
        address seller = offer.seller;
        require (seller != msg.sender, 'seller == msg.sender');
        require (seller == apesContract.ownerOf(id), 'seller no longer owner of apes');

        offers[id] = Offer(false, id, msg.sender, 0, address(0x0));
        
        // Transfer 0xApes to msg.sender from seller.
        apesContract.safeTransferFrom(seller, msg.sender, id);
        
        // Transfer ETH to seller!
        uint commission = 0;
        if(adminPercent > 0) {
            commission = amount * adminPercent / 100;
            adminPending += commission;
        }

        _safeTransferETH(seller, amount - commission);
        
        emit Bought(id, amount, seller, msg.sender, true);

        // refund bid if new owner is buyer!
        Bid memory bid = bids[id];
        if (bid.bidder == msg.sender) {
            _safeTransferETH(bid.bidder, bid.value); 
            bids[id] = Bid(id, address(0x0), 0);
        }
    }

    /* Allows users to enter bids for any 0xApes */
    function placeBid(uint id) payable external whenNotPaused nonReentrant() {
        require (apesContract.ownerOf(id) != msg.sender, 'you already own this apes');
        require (msg.value != 0, 'cannot enter bid of zero');
        Bid memory existing = bids[id];
        require (msg.value > existing.value, 'your bid is too low');
        if (existing.value > 0) {
            // Refund existing bid
            _safeTransferETH(existing.bidder, existing.value); 
        }
        bids[id] = Bid(id, msg.sender, msg.value);
        emit BidEntered(id, msg.value, msg.sender);
    }

    /* Allows 0xApes owners to accept bids for their Apes */
    function acceptBid(uint id, uint minPrice) external onlyApesOwner(id) whenNotPaused nonReentrant() {
        address seller = msg.sender;
        Bid memory bid = bids[id];
        uint amount = bid.value;
        require (amount != 0, 'cannot enter bid of zero');
        require (amount >= minPrice, 'your bid is too low');

        address bidder = bid.bidder;
        require (seller != bidder, 'you already own this token');
        offers[id] = Offer(false, id, bidder, 0, address(0x0));
        bids[id] = Bid(id, address(0x0), 0);
 
        // Transfer 0xApe to  Bidder
        apesContract.safeTransferFrom(msg.sender, bidder, id);

        // Transfer ETH to seller!
        uint commission = 0;
        if(adminPercent > 0) {
            commission = amount * adminPercent / 100;
            adminPending += commission;
        }

        _safeTransferETH(seller, amount - commission);
       
        emit Bought(id, bid.value, seller, bidder, false);
    }

    /* Allows bidders to withdraw their bids */
    function withdrawBid(uint id) external nonReentrant() {
        Bid memory bid = bids[id];
        require(bid.bidder == msg.sender, 'the bidder is not msg sender');
        uint amount = bid.value;
        emit BidWithdrawn(id, amount);
        bids[id] = Bid(id, address(0x0), 0);
        _safeTransferETH(msg.sender, amount);
    }

    receive() external payable {}

    function _safeTransferETH(address to, uint256 value) internal returns(bool) {
		(bool success, ) = to.call{value: value}(new bytes(0));
		return success;
    }

    modifier onlyApesOwner(uint256 tokenId) {
        require(apesContract.ownerOf(tokenId) == msg.sender, "only for apes owner");
        _;
    }
}   