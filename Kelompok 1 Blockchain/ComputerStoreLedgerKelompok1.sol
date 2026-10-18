// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ComputerStoreLedger {
    enum Category { Motherboard, CPU, RAM, GPU, PSU, Storage, Other }
    enum SaleStatus { Completed, Refunded }
    enum Role { None, Cashier, Admin }

    struct Product { Category category; string name; uint256 price; uint256 stock; bool active; }
    struct Accessory { string name; uint256 price; bool active; }
    struct Staff { string name; Role role; bool active; }

    struct SaleInput {
        string buyer;
        uint256 productId;
        uint256 quantity;
        uint256[] accessoryIds;
        string location;
    }

    struct Sale {
        string buyer; uint256 productId; string productName;
        uint256 quantity; string accessories; uint256 total;
        string seller; address recordedBy;
        uint256 stockBefore; uint256 stockAfter;
        string location; SaleStatus status; uint256 refBlock;
    }

    struct LedgerBlock {
        uint256 index; uint256 timestamp; Sale sale;
        bytes32 prevHash; bytes32 hash;
    }

    address public owner;
    mapping(address => Staff) public staffs;
    mapping(uint256 => Product) public products;
    mapping(uint256 => Accessory) public accessories;
    mapping(uint256 => bool) public isRefunded;
    uint256 public productCount;
    uint256 public accessoryCount;
    bool public sampleSeeded;
    LedgerBlock[] private chain;

    event BlockAdded(uint256 indexed index, bytes32 hash, address indexed recordedBy);
    event ProductAdded(uint256 indexed productId, string name, uint256 price, uint256 stock);
    event AccessoryAdded(uint256 indexed accessoryId, string name, uint256 price);
    event Restocked(uint256 indexed productId, uint256 amount, uint256 newStock);
    event StaffUpdated(address indexed account, string name, Role role, bool active);
    event SaleRefunded(uint256 indexed originalBlock, uint256 indexed refundBlock, address indexed by);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() { require(msg.sender == owner, "Hanya owner"); _; }
    modifier onlyStaff() { require(staffs[msg.sender].active, "Bukan staff aktif"); _; }

    constructor() {
        owner = msg.sender;
        staffs[msg.sender] = Staff("Owner", Role.Admin, true);
        Sale memory s;
        s.buyer = "Genesis Block";
        s.recordedBy = msg.sender;
        uint256 ts = block.timestamp;
        bytes32 h = _hashBlock(1, ts, s, bytes32(0));
        chain.push(LedgerBlock(1, ts, s, bytes32(0), h));
        emit BlockAdded(1, h, msg.sender);
        emit StaffUpdated(msg.sender, "Owner", Role.Admin, true);
    }

    // ---- ADMIN ----
    function setStaff(address account, string calldata name, Role role, bool active) external onlyOwner {
        require(account != address(0) && account != owner, "Akun tidak valid");
        require(bytes(name).length > 0 && role != Role.None, "Input tidak valid");
        staffs[account] = Staff(name, role, active);
        emit StaffUpdated(account, name, role, active);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0) && newOwner != owner, "Akun tidak valid");
        address prev = owner;
        owner = newOwner;
        staffs[newOwner] = Staff("Owner", Role.Admin, true);
        emit OwnershipTransferred(prev, newOwner);
        emit StaffUpdated(newOwner, "Owner", Role.Admin, true);
    }

    function addProduct(Category cat, string calldata name, uint256 price, uint256 stock)
        external onlyOwner returns (uint256) { return _addProduct(cat, name, price, stock); }

    function addAccessory(string calldata name, uint256 price)
        external onlyOwner returns (uint256) { return _addAccessory(name, price); }

    function setProductPrice(uint256 id, uint256 price) external onlyOwner {
        require(_validProduct(id) && price > 0, "Input tidak valid");
        products[id].price = price;
    }

    function setProductActive(uint256 id, bool active) external onlyOwner {
        require(_validProduct(id), "Produk tidak ditemukan");
        products[id].active = active;
    }

    function seedSampleCatalog() external onlyOwner {
        require(!sampleSeeded, "Sudah di-seed");
        sampleSeeded = true;
        _addProduct(Category.Motherboard, "AMD AM4 - B550", 1750000, 10);
        _addProduct(Category.CPU, "AMD Ryzen 5 5600", 1850000, 10);
        _addProduct(Category.RAM, "DDR4 16GB", 650000, 20);
        _addProduct(Category.GPU, "NVIDIA RTX 4060", 5200000, 5);
        _addProduct(Category.PSU, "650W 80+ Bronze", 950000, 8);
        _addProduct(Category.Storage, "SSD NVMe Gen4 2TB", 2250000, 6);
        _addAccessory("Kabel HDMI", 100000);
        _addAccessory("Mousepad", 75000);
        _addAccessory("Flashdisk 64GB", 90000);
        _addAccessory("Thermal Paste", 75000);
        _addAccessory("Kabel Power", 50000);
    }

    // ---- STAFF ----
    function restock(uint256 id, uint256 amount) external onlyStaff {
        require(_validProduct(id) && amount > 0, "Input tidak valid");
        products[id].stock += amount;
        emit Restocked(id, amount, products[id].stock);
    }

    function recordSale(SaleInput calldata input) external onlyStaff returns (uint256) {
        require(bytes(input.buyer).length > 0 && bytes(input.location).length > 0, "Input kosong");
        require(input.quantity > 0 && _validProduct(input.productId), "Input tidak valid");
        Product storage p = products[input.productId];
        require(p.active && input.quantity <= p.stock, "Stok/produk tidak valid");
        (uint256 accTotal, string memory accNames) = _accessoryInfo(input.accessoryIds);
        Sale memory s;
        s.buyer = input.buyer; s.productId = input.productId; s.productName = p.name;
        s.quantity = input.quantity; s.accessories = accNames;
        s.total = (p.price + accTotal) * input.quantity;
        s.seller = staffs[msg.sender].name; s.recordedBy = msg.sender;
        s.stockBefore = p.stock; s.location = input.location; s.status = SaleStatus.Completed;
        p.stock -= input.quantity; s.stockAfter = p.stock;
        return _appendBlock(s);
    }

    function refundSale(uint256 blockIndex) external onlyOwner returns (uint256) {
        require(blockIndex > 1 && blockIndex <= chain.length && !isRefunded[blockIndex], "Blok tidak valid");
        Sale memory s = chain[blockIndex - 1].sale;
        require(s.status == SaleStatus.Completed, "Bukan penjualan");
        isRefunded[blockIndex] = true;
        Product storage p = products[s.productId];
        s.stockBefore = p.stock; p.stock += s.quantity; s.stockAfter = p.stock;
        s.status = SaleStatus.Refunded; s.refBlock = blockIndex;
        s.seller = staffs[msg.sender].name; s.recordedBy = msg.sender;
        uint256 refundIndex = _appendBlock(s);
        emit SaleRefunded(blockIndex, refundIndex, msg.sender);
        return refundIndex;
    }

    // ---- VALIDASI & BACA ----
    function verifyChain() public view returns (bool valid, uint256 firstInvalidIndex) {
        for (uint256 i = 0; i < chain.length; i++) {
            LedgerBlock storage b = chain[i];
            if (b.hash != _hashBlock(b.index, b.timestamp, b.sale, b.prevHash))
                return (false, b.index);
            if (i > 0 && b.prevHash != chain[i - 1].hash)
                return (false, b.index);
            if (i == 0 && b.prevHash != bytes32(0))
                return (false, b.index);
        }
        return (true, 0);
    }

    function isChainValid() external view returns (bool) {
        (bool valid, ) = verifyChain();
        return valid;
    }
    function getChainLength() external view returns (uint256) { return chain.length; }
    function getBlock(uint256 index) external view returns (LedgerBlock memory) {
        require(index >= 1 && index <= chain.length, "Blok tidak ada");
        return chain[index - 1];
    }
    function getLatestBlock() external view returns (LedgerBlock memory) { return chain[chain.length - 1]; }
    function calculateHash(uint256 index) external view returns (bytes32) {
        require(index >= 1 && index <= chain.length, "Blok tidak ada");
        LedgerBlock storage b = chain[index - 1];
        return _hashBlock(b.index, b.timestamp, b.sale, b.prevHash);
    }
    function getStock(uint256 id) external view returns (uint256) {
        require(_validProduct(id), "Produk tidak ditemukan");
        return products[id].stock;
    }
    function previewTotal(uint256 id, uint256 qty, uint256[] calldata accIds) external view returns (uint256) {
        require(_validProduct(id), "Produk tidak ditemukan");
        (uint256 accTotal,) = _accessoryInfo(accIds);
        return (products[id].price + accTotal) * qty;
    }

    // ---- INTERNAL ----
    function _hashBlock(uint256 idx, uint256 ts, Sale memory sale, bytes32 prev) internal pure returns (bytes32) {
        return keccak256(abi.encode(idx, ts, sale, prev));
    }

    function _appendBlock(Sale memory s) internal returns (uint256 newIndex) {
        LedgerBlock storage last = chain[chain.length - 1];
        newIndex = last.index + 1;
        uint256 ts = block.timestamp;
        bytes32 h = _hashBlock(newIndex, ts, s, last.hash);
        chain.push(LedgerBlock(newIndex, ts, s, last.hash, h));
        emit BlockAdded(newIndex, h, msg.sender);
    }

    function _accessoryInfo(uint256[] calldata ids) internal view returns (uint256 sum, string memory names) {
        if (ids.length == 0) return (0, "Tidak ada");
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            require(id >= 1 && id <= accessoryCount && accessories[id].active, "Aksesori tidak valid");
            Accessory storage a = accessories[id];
            sum += a.price;
            names = (i == 0) ? a.name : string.concat(names, ", ", a.name);
        }
    }

    function _validProduct(uint256 id) internal view returns (bool) { return id >= 1 && id <= productCount; }

    function _addProduct(Category cat, string memory name, uint256 price, uint256 stock)
        internal returns (uint256 productId) {
        require(bytes(name).length > 0 && price > 0, "Input tidak valid");
        productId = ++productCount;
        products[productId] = Product(cat, name, price, stock, true);
        emit ProductAdded(productId, name, price, stock);
    }

    function _addAccessory(string memory name, uint256 price) internal returns (uint256 accessoryId) {
        require(bytes(name).length > 0 && price > 0, "Input tidak valid");
        accessoryId = ++accessoryCount;
        accessories[accessoryId] = Accessory(name, price, true);
        emit AccessoryAdded(accessoryId, name, price);
    }
}
