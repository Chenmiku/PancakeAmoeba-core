// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../library/SafeBEP20.sol";
import "../library/BEP20.sol";

import "../interfaces/IPancakeRouter02.sol";
import "../interfaces/IPancakePair.sol";
import "../interfaces/IAMVStrategy.sol";
import "../interfaces/IAMVMinterV2.sol";
import "../interfaces/IAMVChef.sol";
import "../library/PausableUpgradeable.sol";


abstract contract VaultAMVController is IVaultAMVController, PausableUpgradeable {
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANT VARIABLES ========== */
    BEP20 private constant AMV = BEP20(0x76383afd3C3501C2b0f5B4450E819eD430Ce4de0);

    /* ========== STATE VARIABLES ========== */

    address public keeper;
    IBEP20 internal _stakingToken;
    IAMVMinterV2 internal _minter;
    IAMVChef internal _amvChef;

    /* ========== VARIABLE GAP ========== */

    uint256[49] private __gap;

    /* ========== Event ========== */

    event Recovered(address token, uint amount);


    /* ========== MODIFIERS ========== */

    modifier onlyKeeper {
        require(msg.sender == keeper || msg.sender == owner(), 'VaultController: caller is not the owner or keeper');
        _;
    }

    /* ========== INITIALIZER ========== */

    function __VaultController_init(IBEP20 token) internal initializer {
        __PausableUpgradeable_init();

        keeper = 0x69acAf38Bcd090E2F888e0B2409c7031c005d760;
        _stakingToken = token;
    }

    /* ========== VIEWS FUNCTIONS ========== */

    function minter() external view override returns (address) {
        return canMint() ? address(_minter) : address(0);
    }

    function canMint() internal view returns (bool) {
        return address(_minter) != address(0) && _minter.isMinter(address(this));
    }

    function amvChef() external view override returns (address) {
        return address(_amvChef);
    }

    function stakingToken() external view override returns (address) {
        return address(_stakingToken);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setKeeper(address _keeper) external onlyKeeper {
        require(_keeper != address(0), 'VaultController: invalid keeper address');
        keeper = _keeper;
    }

    function setMinter(address newMinter) virtual public onlyOwner {
        // can zero
        _minter = IAMVMinterV2(newMinter);
        if (newMinter != address(0)) {
            require(newMinter == AMV.getOwner(), 'VaultController: not amv minter');
            _stakingToken.safeApprove(newMinter, 0);
            _stakingToken.safeApprove(newMinter, uint(~0));
        }
    }

    function setAMVChef(IAMVChef newAMVChef) virtual public onlyOwner {
        require(address(_amvChef) == address(0), 'VaultController: setAMVChef only once');
        _amvChef = newAMVChef;
    }

    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address _token, uint amount) virtual external onlyOwner {
        require(_token != address(_stakingToken), 'VaultController: cannot recover underlying token');
        IBEP20(_token).safeTransfer(owner(), amount);

        emit Recovered(_token, amount);
    }
}