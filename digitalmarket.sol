// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract DigitalMarket {
    /*
     *   Type Declarations
     *   struct Product
     *   constant uint256 FEE_DENOMINATOR, MAX_PLATFORM_FEE, MAX_LISTING_FEE
     *   constant bool _IS_TEST
     */
    struct Product {
        uint256 id;
        string name;
        string description;
        uint256 price;
        string ipfsHash;
        address payable owner;
        bool status;
        uint256 createdAt;
    }

    uint256 public constant FEE_DENOMINATOR = 10000; // Fee Divisor (100%)
    uint256 public constant MAX_PLATFORM_FEE = 1000; // Platform Maxfee 10%
    uint256 public constant MAX_LISTING_FEE = 1000; // Product Listing maxfee 10%

    bool private constant _IS_TEST = true;

    /*
     *   State Variables
     *   private address _platformOwner, _productIdCounter
     *   public uint256 productIdCounter, platformFee, listingFee
     *   public mapping products, user2products
     */

    address private _platformOwner;
    uint256 private _productIdCounter;

    uint256 public platformFee = 500; // MarketPlace Platform Fee -> default 5%
    uint256 public listingFee = 500; // Product Listing Fee -> default 5%

    mapping(uint256 => Product) public products;
    mapping(address => mapping(uint256 => bool)) public user2products;

    /*
     *   Events
     *   ProductListed, ProductPurchased, OwnershipTransferred, FundsWithdrawn, ProductStatusChanged
     *   PlatformOwnerChanged, PlatformFeeUpdated, ListingFeeUpdated
     */

    event ProductListed(
        uint256 indexed productId,
        string name,
        uint256 price,
        address indexed owner,
        string ipfsHash
    );

    event ProductPurchased(
        uint256 indexed productId,
        address indexed previousOwner,
        address indexed newOwner,
        uint256 price,
        uint256 platformFee
    );

    event OwnershipTransferred(
        uint256 indexed productId,
        address indexed previousOwner,
        address indexed newOwner
    );

    event FundsWithdrawn(address indexed owner, uint256 amount);

    event ProductStatusChanged(
        address indexed owner,
        uint256 indexed productId,
        bool enabled
    );

    event PlatformOwnerChanged(address oldOwner, address newOwner);

    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);

    event ListingFeeUpdated(uint256 oldFee, uint256 newFee);

    /*
     *  MODIFIERS
     *  productExisting, onlyProductOwner, onlyPlatformOwner, sufficientBalance
     *
     */

    modifier productExisting(uint256 productId) {
        require(productId > 0, "Invalid Product Id");
        require(productId <= _productIdCounter, "Product does not exist");
        _;
    }

    modifier onlyProductOwner(uint256 productId) {
        require(products[productId].owner == msg.sender, "Not product owner");
        _;
    }

    modifier onlyPlatformOwner() {
        require(
            _platformOwner == msg.sender,
            "Only the platform owner can do this"
        );
        _;
    }

    modifier validPrice(uint256 price) {
        require(price > 0, "Invalid price");
        _;
    }

    modifier sufficientBalance(uint256 price) {
        require(msg.sender.balance >= price, "Unsufficient balance");
        _;
    }

    /*
     *  Functions
     *  listProduct, purchaseProduct, transferOwnership, withdrawFunds
     *  updatePlatformOwner, updatePlatformFee, updateListingFee
     *  updateProductStatus, getProduct, isUserOwningPRoduct, getTotalProductCount
     *  calculatePlatformFeePrice, calculateListingFeePrice
     */

    constructor(uint256 _platformFee, uint256 _listingFee) {
        _platformOwner = msg.sender;

        platformFee = _platformFee;
        listingFee = _listingFee;
    }

    // FallBacks
    receive() external payable {}
    fallback() external payable {}

    /*
     * list Product
     * @params (string name, string description, uint256 price, string ipfsHash)
     * @returns(productId)
     */
    function listProduct(
        string calldata name,
        string calldata description,
        uint256 price,
        string calldata ipfsHash
    )
        external
        payable
        validPrice(price)
        sufficientBalance(price)
        returns (uint256 productId)
    {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(ipfsHash).length > 0, "IPFS hash requiredd");
        require(
            msg.value >= calculateListingFeePrice(price),
            "Insufficient pay amount for listing a product"
        );

        // List a product
        address contractAddress = address(this);
        address ownerAddress = msg.sender;

        productId = ++_productIdCounter;

        products[productId] = Product({
            id: productId,
            name: name,
            description: description,
            price: price,
            ipfsHash: ipfsHash,
            owner: payable(_IS_TEST ? contractAddress : ownerAddress),
            status: true,
            createdAt: block.timestamp
        });

        user2products[_IS_TEST ? contractAddress : ownerAddress][
            productId
        ] = true;

        emit ProductListed(
            productId,
            name,
            price,
            _IS_TEST ? contractAddress : ownerAddress,
            ipfsHash
        );
    }

    /*
     * Purchase Product
     * @params (uint256 productId)
     * @returns void
     */
    function purchaseProduct(
        uint256 productId
    ) external payable productExisting(productId) {
        Product storage product = products[productId];

        require(product.status, "Product is not enabled");
        require(product.owner != msg.sender, "Cannot buy own product");
        require(msg.value >= product.price, "Insufficient ETH sent");

        address payable productOwnerAddress = product.owner;
        address payable buyerAddress = payable(msg.sender);

        uint256 feeAmount = (product.price * platformFee) / FEE_DENOMINATOR;
        uint256 ownerAmount = product.price - feeAmount;

        // Remove productId from previous owner's list
        user2products[product.owner][productId] = false;

        // Set new owner and add productId to new owner's list
        product.owner = buyerAddress;
        user2products[buyerAddress][productId] = true;

        // Send ETH
        (bool success, ) = productOwnerAddress.call{value: ownerAmount}("");
        require(success, "Transfer ETH to owner failed");

        // Refund remaining ETH
        if (msg.value > product.price) {
            (bool refundSuccess, ) = buyerAddress.call{
                value: msg.value - product.price
            }("");
            require(refundSuccess, "Refund remaining ETH failed");
        }

        emit ProductPurchased(
            productId,
            productOwnerAddress,
            buyerAddress,
            product.price,
            platformFee
        );
    }

    /*
     * Transfer Ownership
     * @params (uint256 productId, address newOwner)
     * @returns void
     */
    function transferOwnership(
        uint256 productId,
        address newOwner
    ) external productExisting(productId) onlyProductOwner(productId) {
        require(newOwner != msg.sender, "Cannot transfer to self");

        Product storage product = products[productId];
        address previousOwner = product.owner;

        // Remove productId from previous owner's list
        user2products[product.owner][productId] = false;

        // Set new owner and add productId to new owner's list
        product.owner = payable(newOwner);
        user2products[newOwner][productId] = true;

        emit OwnershipTransferred(productId, previousOwner, newOwner);
    }

    /*
     * Withdraw listing fee + transaction fee to platform owner
     * @params void
     * @returns void
     */
    function withdrawFunds() external onlyPlatformOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");

        (bool success, ) = payable(_platformOwner).call{value: balance}("");
        require(success, "Withdraw funds failed");

        emit FundsWithdrawn(_platformOwner, balance);
    }

    /*
     * Update Platform Owner
     * @params (address newOwner)
     * @return void
     */
    function updatePlatformOwner(address newOwner) external onlyPlatformOwner {
        address oldOwner = _platformOwner;
        _platformOwner = newOwner;

        emit PlatformOwnerChanged(oldOwner, newOwner);
    }

    /*
     * Update PlatformFee
     * @params (uint256 newFee)
     * @returns void
     */
    function updatePlatformFee(uint256 newFee) external onlyPlatformOwner {
        require(newFee <= MAX_PLATFORM_FEE, "Platform Fee cannot exceed 10%");

        uint256 oldFee = platformFee;
        platformFee = newFee;

        emit PlatformFeeUpdated(oldFee, newFee);
    }

    /*
     * Update ListingFee
     * @params (uint256 newFee)
     * @returns void
     */
    function updateListingFee(uint256 newFee) external onlyPlatformOwner {
        require(newFee <= MAX_LISTING_FEE, "Listing Fee cannot exceed 10%");

        uint256 oldFee = listingFee;
        listingFee = newFee;

        emit ListingFeeUpdated(oldFee, newFee);
    }

    /*
     * Update Product Status
     * @params (uint256 productId, bool enabled)
     * @returns (void)
     */
    function updateProductStatus(
        uint256 productId,
        bool status
    ) external productExisting(productId) {
        require(
            products[productId].owner == msg.sender,
            "Only owner can do this"
        );
        products[productId].status = status;

        emit ProductStatusChanged(msg.sender, productId, status);
    }

    /*
     * Get Product Details
     * @params (uint256 productId)
     * @returns (Product)
     */
    function getProduct(
        uint256 productId
    ) external view productExisting(productId) returns (Product memory) {
        return products[productId];
    }

    /*
     * Check if user owns a product
     * @params (uint256 productId)
     * @returns bool
     */
    function isUserOwningProduct(
        uint256 productId
    ) external view productExisting(productId) returns (bool) {
        if (products[productId].owner == msg.sender) return true;
        else return false;
    }

    /*
     * Get Total Product Count
     * @params (void)
     * @returns (uint256)
     */
    function getTotalProductCount() external view returns (uint256) {
        return _productIdCounter;
    }

    /*
     * Calculate platform fee
     * @params (uint256 price)
     * @returns (uint256)
     */
    function calculatePlatformFeePrice(
        uint256 price
    ) public view returns (uint256) {
        return (price * platformFee) / FEE_DENOMINATOR;
    }

    /*
     * Calculate listing fee
     * @params (uint256 price)
     * @returns (uint256)
     */
    function calculateListingFeePrice(
        uint256 price
    ) public view returns (uint256) {
        return (price * listingFee) / FEE_DENOMINATOR;
    }
}
