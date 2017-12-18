/// cdpContainer.sol -- simplified CDP engine (baby brother of `vat')

// Copyright (C) 2017  Nikolai Mushegian <nikolai@dapphub.com>
// Copyright (C) 2017  Daniel Brockman <daniel@dapphub.com>
// Copyright (C) 2017  Rain Break <rainbreak@riseup.net>

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.4.18;

import "ds-thing/thing.sol";
import "ds-token/token.sol";
import "ds-value/value.sol";

import "./vox.sol";

contract DaiCdpContainerEvents {
    event LogNewCdp(address indexed owner, bytes32 cdp);
}

contract DaiCdpContainer is DSThing, DaiCdpContainerEvents {
    DSToken  public  dai;  // Stablecoin
    DSToken  public  sin;  // Debt (negative dai)

    DSToken  public  peth;  // Abstracted collateral
    ERC20    public  weth;  // Underlying collateral

    DSToken  public  mkr;  // Governance token

    DaiVox   public  vox;  // Target price feed
    DSValue  public  usdPerEth;  // Reference price feed
    DSValue  public  daiPerMaker;  // Governance price feed

    address  public  liquidator;  // Liquidator
    address  public  pit;  // Governance Vault

    uint256  public  liquidationPenalty27;  // Liquidation penalty
    uint256  public  debtCeiling;  // Debt ceiling
    uint256  public  liquidationRatio27;  // Liquidation ratio
    uint256  public  stabilityFee27;  // Stability fee
    uint256  public  governanceFee27;  // Governance fee
    uint256  public  wethToPethSpread18;  // Join-Exit Spread

    bool     public  off;  // Cage flag
    bool     public  out;  // Post triggerGlobalSettlement sellPethForWeth

    uint256  public  usdPerPethAtSettlement;  // REF per PETH (just before settlement)

    uint256  public  timestampOfLastFeeAccumulation;  // Time of last drip
    uint256         _chi;  // Accumulated StabilityFee Rates
    uint256         _rhi;  // Accumulated StabilityFee + Fee Rates
    uint256  public  rum;  // Total normalised debt

    uint256                   public  lastCdp;
    mapping (bytes32 => Cdp)  public  cdps;

    struct Cdp {
        address  owner;      // CDP owner
        uint256  pethCollateral;      // Locked collateral (in PETH)
        uint256  outstandingDebtAndStabilityFees;      // Outstanding normalised debt (stability fee only)
        uint256  ire;      // Outstanding normalised debt
    }

    function getOwner(bytes32 cdp) public view returns (address) {
        return cdps[cdp].owner;
    }
    function getPethCollateral(bytes32 cdp) public view returns (uint) {
        return cdps[cdp].pethCollateral;
    }
    function tab(bytes32 cdp) public returns (uint) {
        return rmul(cdps[cdp].outstandingDebtAndStabilityFees, chi());
    }
    function rap(bytes32 cdp) public returns (uint) {
        return sub(rmul(cdps[cdp].ire, rhi()), tab(cdp));
    }

    // Total CDP Debt
    function din() public returns (uint) {
        return rmul(rum, chi());
    }
    // Backing collateral
    function totalCollateralizedPeth() public view returns (uint) {
        return peth.balanceOf(this);
    }
    // Raw collateral
    function wethLockedInPeth() public view returns (uint) {
        return weth.balanceOf(this);
    }

    //------------------------------------------------------------------

    function DaiCdpContainer(
        DSToken  dai_,
        DSToken  sin_,
        DSToken  peth_,
        ERC20    weth_,
        DSToken  mkr_,
        DSValue  usdPerEth_,
        DSValue  daiPerMaker_,
        DaiVox   vox_,
        address  pit_
    ) public {
        weth = weth_;
        peth = peth_;

        dai = dai_;
        sin = sin_;

        mkr = mkr_;
        pit = pit_;

        usdPerEth = usdPerEth_;
        daiPerMaker = daiPerMaker_;
        vox = vox_;

        liquidationPenalty27 = ONE_27;
        liquidationRatio27 = ONE_27;
        stabilityFee27 = ONE_27;
        governanceFee27 = ONE_27;
        wethToPethSpread18 = ONE_18;

        _chi = ONE_27;
        _rhi = ONE_27;

        timestampOfLastFeeAccumulation = getCurrentTimestamp();
    }

    function getCurrentTimestamp() public constant returns (uint) {
        return block.timestamp;
    }

    //--Risk-parameter-config-------------------------------------------

    function mold(bytes32 param, uint val) public note auth {
        if      (param == 'debtCeiling') debtCeiling = val;
        else if (param == 'liquidationRatio27') { require(val >= ONE_27); liquidationRatio27 = val; }
        else if (param == 'stabilityFee27') { require(val >= ONE_27); drip(); stabilityFee27 = val; }
        else if (param == 'governanceFee27') { require(val >= ONE_27); drip(); governanceFee27 = val; }
        else if (param == 'liquidationPenalty27') { require(val >= ONE_27); liquidationPenalty27 = val; }
        else if (param == 'wethToPethSpread18') { require(val >= ONE_18); wethToPethSpread18 = val; }
        else return;
    }

    //--Price-feed-setters----------------------------------------------

    function setUsdPerEth(DSValue usdPerEth_) public note auth {
        usdPerEth = usdPerEth_;
    }
    function setDaiPerMaker(DSValue daiPerMaker_) public note auth {
        daiPerMaker = daiPerMaker_;
    }
    function setVox(DaiVox vox_) public note auth {
        vox = vox_;
    }

    //--Tap-setter------------------------------------------------------
    function turn(address tap_) public note {
        require(liquidator  == 0);
        require(tap_ != 0);
        liquidator = tap_;
    }

    //--Collateral-wrapper----------------------------------------------

    // Wrapper ratio (weth per peth)
    function wethPerPeth() public view returns (uint ray) {
        return peth.totalSupply() == 0 ? ONE_27 : rdiv(wethLockedInPeth(), peth.totalSupply());
    }
    // Join price (weth per peth)
    function ask(uint wad) public view returns (uint) {
        return rmul(wad, wmul(wethPerPeth(), wethToPethSpread18));
    }
    // Exit price (weth per peth)
    function bid(uint wad) public view returns (uint) {
        return rmul(wad, wmul(wethPerPeth(), sub(2 * ONE_18, wethToPethSpread18)));
    }
    function buyPethWithWeth(uint wad) public note {
        require(!off);
        require(ask(wad) > 0);
        require(weth.transferFrom(msg.sender, this, ask(wad)));
        peth.mint(msg.sender, wad);
    }
    function sellPethForWeth(uint wad) public note {
        require(!off || out);
        require(weth.transfer(msg.sender, bid(wad)));
        peth.burn(msg.sender, wad);
    }

    //--Stability-governanceFee27-accumulation--------------------------------------

    // Accumulated Rates
    function chi() public returns (uint) {
        drip();
        return _chi;
    }
    function rhi() public returns (uint) {
        drip();
        return _rhi;
    }
    function drip() public note {
        if (off) return;

        var timestampOfLastFeeAccumulation_ = getCurrentTimestamp();
        var age = timestampOfLastFeeAccumulation_ - timestampOfLastFeeAccumulation;
        if (age == 0) return;    // optimised
        timestampOfLastFeeAccumulation = timestampOfLastFeeAccumulation_;

        var inc = ONE_27;

        if (stabilityFee27 != ONE_27) {  // optimised
            var _chi_ = _chi;
            inc = rpow(stabilityFee27, age);
            _chi = rmul(_chi, inc);
            dai.mint(liquidator, rmul(sub(_chi, _chi_), rum));
        }

        // optimised
        if (governanceFee27 != ONE_27) inc = rmul(inc, rpow(governanceFee27, age));
        if (inc != ONE_27) _rhi = rmul(_rhi, inc);
    }


    //--CDP-risk-indicator----------------------------------------------

    // Abstracted collateral price (ref per peth)
    function usdPerPeth() public view returns (uint wad) {
        return off ? usdPerPethAtSettlement : wmul(wethPerPeth(), uint(usdPerEth.read()));
    }
    // Returns true if cdp is well-collateralized
    function isAboveMarginCallThreshold(bytes32 cdp) public returns (bool) {
        var pro = rmul(usdPerPeth(), getPethCollateral(cdp));
        var con = rmul(vox.par(), tab(cdp));
        var min = rmul(con, liquidationRatio27);
        return pro >= min;
    }


    //--CDP-operations--------------------------------------------------

    function open() public note returns (bytes32 cdp) {
        require(!off);
        lastCdp = add(lastCdp, 1);
        cdp = bytes32(lastCdp);
        cdps[cdp].owner = msg.sender;
        LogNewCdp(msg.sender, cdp);
    }
    function transferOwnership(bytes32 cdp, address newOwner) public note {
        require(msg.sender == cdps[cdp].owner);
        require(newOwner != 0);
        cdps[cdp].owner = newOwner;
    }

    function depositPeth(bytes32 cdp, uint wad) public note {
        require(!off);
        cdps[cdp].pethCollateral = add(cdps[cdp].pethCollateral, wad);
        peth.pull(msg.sender, wad);
        require(cdps[cdp].pethCollateral == 0 || cdps[cdp].pethCollateral > 0.005 ether);
    }
    function withdrawPeth(bytes32 cdp, uint wad) public note {
        require(msg.sender == cdps[cdp].owner);
        cdps[cdp].pethCollateral = sub(cdps[cdp].pethCollateral, wad);
        peth.push(msg.sender, wad);
        require(isAboveMarginCallThreshold(cdp));
        require(cdps[cdp].pethCollateral == 0 || cdps[cdp].pethCollateral > 0.005 ether);
    }

    function withdrawDai(bytes32 cdp, uint wad) public note {
        require(!off);
        require(msg.sender == cdps[cdp].owner);
        require(rdiv(wad, chi()) > 0);

        cdps[cdp].outstandingDebtAndStabilityFees = add(cdps[cdp].outstandingDebtAndStabilityFees, rdiv(wad, chi()));
        rum = add(rum, rdiv(wad, chi()));

        cdps[cdp].ire = add(cdps[cdp].ire, rdiv(wad, rhi()));
        dai.mint(cdps[cdp].owner, wad);

        require(isAboveMarginCallThreshold(cdp));
        require(dai.totalSupply() <= debtCeiling);
    }
    function depositDai(bytes32 cdp, uint wad) public note {
        require(!off);

        var owe = rmul(wad, rdiv(rap(cdp), tab(cdp)));

        cdps[cdp].outstandingDebtAndStabilityFees = sub(cdps[cdp].outstandingDebtAndStabilityFees, rdiv(wad, chi()));
        rum = sub(rum, rdiv(wad, chi()));

        cdps[cdp].ire = sub(cdps[cdp].ire, rdiv(add(wad, owe), rhi()));
        dai.burn(msg.sender, wad);

        var (val, ok) = daiPerMaker.peek();
        if (ok && val != 0) mkr.move(msg.sender, pit, wdiv(owe, uint(val)));
    }

    function shut(bytes32 cdp) public note {
        require(!off);
        require(msg.sender == cdps[cdp].owner);
        if (tab(cdp) != 0) depositDai(cdp, tab(cdp));
        if (getPethCollateral(cdp) != 0) withdrawPeth(cdp, getPethCollateral(cdp));
        delete cdps[cdp];
    }

    function marginCall(bytes32 cdp) public note {
        require(!isAboveMarginCallThreshold(cdp) || off);

        // Take on all of the debt, except unpaid fees
        var rue = tab(cdp);
        sin.mint(liquidator, rue);
        rum = sub(rum, cdps[cdp].outstandingDebtAndStabilityFees);
        cdps[cdp].outstandingDebtAndStabilityFees = 0;
        cdps[cdp].ire = 0;

        // Amount owed in PETH, including liquidation penalty
        var owe = rdiv(rmul(rmul(rue, liquidationPenalty27), vox.par()), usdPerPeth());

        if (owe > cdps[cdp].pethCollateral) {
            owe = cdps[cdp].pethCollateral;
        }

        peth.push(liquidator, owe);
        cdps[cdp].pethCollateral = sub(cdps[cdp].pethCollateral, owe);
    }

    //------------------------------------------------------------------

    function triggerGlobalSettlement(uint usdPerPethAtSettlement_, uint jam) public note auth {
        require(!off && usdPerPethAtSettlement_ != 0);
        off = true;
        liquidationPenalty27 = ONE_27;
        wethToPethSpread18 = ONE_18;
        usdPerPethAtSettlement = usdPerPethAtSettlement_;         // ref per peth
        require(weth.transfer(liquidator, jam));
    }
    function flow() public note auth {
        require(off);
        out = true;
    }
}
