// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../library/Math.sol";
import "../library/SafeMath.sol";
import "../library/SafeBEP20.sol";
import "../library/ReentrancyGuardUpgradeable.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IAMVChef.sol";
import "../interfaces/IAMVMinterV2.sol";
import "./VaultAMVController.sol";
import {PoolConstant} from "../library/PoolConstant.sol";


contract VaultFlipToToken is VaultAMVController, IAMVStrategy, ReentrancyGuardUpgradeable {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANTS ============= */

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant AMV = 0x76383afd3C3501C2b0f5B4450E819eD430Ce4de0; // require mainnet
    IAMVChef private constant AMV_CHEF = IAMVChef(0x6DF415431E916E10836FbE52A22Bca44ddf06C08); // require mainnet
    
    IPancakeRouter02 private constant ROUTER = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    
    PoolConstant.PoolTypes public constant override poolType = PoolConstant.PoolTypes.AMVBNB;

    /* ========== STATE VARIABLES ========== */

    address public tokenReward;
    uint public override pid;
    uint private _totalSupply;
    mapping(address => uint) private _balances;

    mapping (address => uint) private _depositedAt;

    /* ========== INITIALIZER ========== */

    function initialize(address _tokenStake, address _tokenReward) external initializer {
        __VaultController_init(IBEP20(_tokenStake));
        __ReentrancyGuard_init();
        
        tokenReward = _tokenReward;
        setMinter(0xC7EBF06A6188040B45fe95112Ff5557c36Ded7c0); // require mainnet
        setAMVChef(AMV_CHEF);
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view override returns (uint) {
        return _totalSupply;
    }

    function balance() override external view returns (uint) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint) {
        return _balances[account];
    }

    function sharesOf(address account) external view override returns (uint) {
        return _balances[account];
    }

    function principalOf(address account) external view override returns (uint) {
        return _balances[account];
    }

    function depositedAt(address account) external view override returns (uint) {
        return _depositedAt[account];
    }

    function withdrawableBalanceOf(address account) public view override returns (uint) {
        return _balances[account];
    }

    function priceShare() external view override returns(uint) {
        return 1e18;
    }
    
    function earned(address) override public view returns (uint) {
        return 0;
    }
    
    function rewardsToken() external view override returns (address) {
        return tokenReward;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function _deposit(uint amount, address _to) private nonReentrant notPaused {
        require(amount > 0, "VaultFlipToToken: amount must be greater than zero");
        _totalSupply = _totalSupply.add(amount);
        _balances[_to] = _balances[_to].add(amount);
        _depositedAt[_to] = block.timestamp;
        _stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        AMV_CHEF.notifyDeposited(msg.sender, amount);
        emit Deposited(_to, amount);

        // _harvest();
    }

    function deposit(uint amount) override public {
        _deposit(amount, msg.sender);
    }

    function depositAll() override external {
        deposit(_stakingToken.balanceOf(msg.sender));
    }

    function withdraw(uint amount) override public {
        require(amount > 0, "VaultFlipToToken: amount must be greater than zero");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        AMV_CHEF.notifyWithdrawn(msg.sender, amount);
        _stakingToken.safeTransfer(msg.sender, amount);
    
        // _harvest();
    }

    function withdrawAll() external override {
        getReward();
        uint _withdraw = withdrawableBalanceOf(msg.sender);
        if (_withdraw > 0) {
            withdraw(_withdraw);
        }
    }

    function getReward() public override nonReentrant {
        uint pendingAMV = AMV_CHEF.pendingAMV(address(this), msg.sender);
        if (pendingAMV > 0) {
            AMV_CHEF.safeAMVTransferToVaults(msg.sender);
            _swapTokenToToken(AMV, pendingAMV.mul(7).div(10), tokenReward, msg.sender);
            IBEP20(AMV).safeTransfer(msg.sender, pendingAMV.mul(3).div(10));
        }
    }

    function harvest() public override {
        revert('N/A');
    }

    // function _harvest() private {
       
    // }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setMinter(address _minter) override public onlyOwner {
        VaultAMVController.setMinter(_minter);
        if (address(_minter) != address(0)) {
            IBEP20(AMV).safeApprove(address(_minter), 0);
            IBEP20(AMV).safeApprove(address(_minter), uint(~0));
        }
    }

    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address tokenAddress, uint tokenAmount) external override onlyOwner {
        require(tokenAddress != address(_stakingToken), "VaultFlipToToken: cannot recover underlying token");
        IBEP20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
    
     /* ========== PRIVATE FUNCTION ========== */
    
     function _approveTokenIfNeeded(address token) private {
        if (IBEP20(token).allowance(address(this), address(ROUTER)) == 0) {
            IBEP20(token).safeApprove(address(ROUTER), uint(~0));
        }
    }
    
    function _swapTokenToToken(address _from, uint amount, address _to, address _receiver) private returns (uint) {
        
        require(amount > 0, "VaultFlipToToken: amount must be greater than zero");
        _approveTokenIfNeeded(_from);

        address[] memory path;
        
        if (_from == WBNB || _to == WBNB) {
            // [WBNB, AMV] or [AMV, WBNB]
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            // [USDT, AMV] or [AMV, USDT]
            path = new address[](3);
            path[0] = _from;
            path[1] = WBNB;
            path[2] = _to;
        }
       
        uint[] memory amounts = ROUTER.swapExactTokensForTokens(amount, 0, path, _receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }
}
