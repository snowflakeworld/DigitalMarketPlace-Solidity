// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract DigitalMarket {
    uint256 private productIdCounter;
    address public platformOwner;
    uint256 public platformFee = 500; // default 5%

    uint256 public constant FEE_DENOMINATOR = 10000; // Divisor
    uint256 public constant MAX_FEE = 1000; // maxfee 10%

    bool public constant IS_TEST = true;

    constructor() {
        platformOwner = msg.sender;
    }

    struct Product {
        uint256 id;
        string name;
        string description;
        uint256 price;
        string ipfsHash;
        address payable owner;
        bool isEnabled;
        uint256 createdAt;
    }

    mapping(uint256 => Product) public products;
    mapping(address => uint256[]) public userProducts;

    /*
     *  EVENTS
     *  ProductMinted, ProductPurchased, OwnershipTransferred, PlatformFeeUpdated, WithdrawnFunds
     *
     */
    event ProductMinted(
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

    event ProductAvailabilityChanged(
        address indexed owner,
        uint256 indexed productId,
        bool enabled
    );

    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);

    event FundsWithdrawn(address indexed owner, uint256 amount);

    /*
     *  MODIFIERS
     *  productExists, onlyProductOwner
     *
     */

    modifier productExists(uint256 productId) {
        require(productId < productIdCounter, "Product does not exist.");
        _;
    }

    modifier onlyProductOwner(uint256 productId) {
        require(products[productId].owner == msg.sender, "Not product owner");
        _;
    }

    modifier onlyPlatformOwner() {
        require(
            platformOwner == msg.sender,
            "Only the platform owner can do this."
        );
        _;
    }

    // FUNCTIONS

    /*
     * Remote product from user products(Internal)
     * @params (address user, uint256 productId)
     * @returns(void)
     */
    function remoteFromUserProducts(
        address owner,
        uint256 productId
    ) internal productExists(productId) {
        for (uint256 i = 0; i < userProducts[owner].length; ++i) {
            if (userProducts[owner][i] == productId) {
                userProducts[owner][i] = userProducts[owner][
                    userProducts[owner].length - 1
                ];
                userProducts[owner].pop();
                break;
            }
        }
    }

    /*
     * Mint Product
     * @params (string name, string description, uint256 price, string ipfsHash)
     * @returns(productId)
     */
    function mintProduct(
        string calldata name,
        string calldata description,
        uint256 price,
        string calldata ipfsHash
    ) external returns (uint256) {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(price > 0, "Price must be greater than 0");
        require(bytes(ipfsHash).length > 0, "IPFS hash requiredd");

        uint256 productId = ++productIdCounter;

        products[productId] = Product({
            id: productId,
            name: name,
            description: description,
            price: price,
            ipfsHash: ipfsHash,
            owner: payable(IS_TEST ? address(this) : msg.sender),
            isEnabled: true,
            createdAt: block.timestamp
        });

        userProducts[IS_TEST ? address(this) : msg.sender].push(productId);

        emit ProductMinted(
            productId,
            name,
            price,
            IS_TEST ? address(this) : msg.sender,
            ipfsHash
        );

        return productId;
    }

    /*
     * Purchase Product
     * @params (uint256 productId)
     * @returns void
     */
    function purchaseProduct(
        uint256 productId
    ) external payable productExists(productId) {
        Product storage product = products[productId];

        require(product.isEnabled, "Product is not enabled");
        require(product.owner != msg.sender, "Cannot buy own product");
        require(msg.value >= product.price, "Insufficient ETH sent");

        address payable previousOwner = product.owner;
        uint256 feeAmount = (product.price * platformFee) / FEE_DENOMINATOR;
        uint256 ownerAmount = product.price - feeAmount;

        // Remove productId from previous owner's list
        remoteFromUserProducts(product.owner, productId);

        // Set new owner and add productId to new owner's list
        product.owner = payable(msg.sender);
        userProducts[msg.sender].push(productId);

        // Send ETH
        (bool success, ) = previousOwner.call{value: ownerAmount}("");
        require(success, "Transfer ETH to owner failed");

        // Refund remaining ETH
        if (msg.value > product.price) {
            (bool refundSuccess, ) = payable(msg.sender).call{
                value: msg.value - product.price
            }("");
            require(refundSuccess, "Refund remaining ETH failed");
        }

        emit ProductPurchased(
            productId,
            previousOwner,
            msg.sender,
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
    ) external productExists(productId) onlyProductOwner(productId) {
        require(newOwner != msg.sender, "Cannot transfer to self");

        Product storage product = products[productId];
        address previousOwner = product.owner;

        // Remove productId from previous owner's list
        remoteFromUserProducts(product.owner, productId);

        // Set new owner and add productId to new owner's list
        product.owner = payable(newOwner);
        userProducts[newOwner].push(productId);

        emit OwnershipTransferred(productId, previousOwner, newOwner);
    }

    /*
     * Update PlatformFee
     * @params (uint256 newFee)
     * @returns void
     */
    function updatePlatformFee(uint256 newFee) external onlyPlatformOwner {
        require(newFee <= MAX_FEE, "Fee cannot exceed 10%");

        uint256 oldFee = platformFee;
        platformFee = newFee;

        emit PlatformFeeUpdated(oldFee, newFee);
    }

    /*
     * Withdraw transaction fee
     * @params void
     * @returns void
     */
    function WithdrawFunds() external onlyPlatformOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");

        (bool success, ) = payable(platformOwner).call{value: balance}("");
        require(success, "Withdraw funds failed");

        emit FundsWithdrawn(platformOwner, balance);
    }

    /*
     * Update Product Availability
     * @params (uint256 productId, bool enabled)
     * @returns (void)
     */
    function updateProductAvailability(
        uint256 productId,
        bool enabled
    ) external productExists(productId) {
        require(
            products[productId].owner == msg.sender,
            "Only owner can do this"
        );
        products[productId].isEnabled = enabled;

        emit ProductAvailabilityChanged(msg.sender, productId, enabled);
    }

    /*
     * Get Product Details
     * @params (uint256 productId)
     * @returns (Product)
     */
    function getProduct(
        uint256 productId
    ) external view productExists(productId) returns (Product memory) {
        return products[productId];
    }

    /*
     * Get User Product Ids
     * @params (address user)
     * @returns (uint256[])
     */
    function getUserProductIds(
        address user
    ) external view returns (uint256[] memory) {
        return userProducts[user];
    }

    /*
     * Get Total Product Count
     * @params (void)
     * @returns (uint256)
     */
    function getTotalProductCount() external view returns (uint256) {
        return productIdCounter;
    }

    /*
     * Calculate fee
     * @params (uint256 price)
     * @returns (uint256)
     */
    function calculateFee(uint256 price) external view returns (uint256) {
        return (price * platformFee) / FEE_DENOMINATOR;
    }

    // FallBacks
    receive() external payable {}
    fallback() external payable {}
}
