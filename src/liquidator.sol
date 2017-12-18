/// liquidator.sol -- liquidation engine (see also `vow`)

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

import "./cdpContainer.sol";

contract DaiTap is DSThing {
    DSToken  public  dai;
    DSToken  public  sin;
    DSToken  public  peth;

    DaiVox   public  vox;
    DaiCdpContainer   public  cdpContainer;

    uint256  public  wethToPethSpread18;  // Boom-Bust Spread
    bool     public  off;  // Cage flag
    uint256  public  wethPerDaiAtSettlement;  // Cage price

    // Surplus
    function joy() public view returns (uint) {
        return dai.balanceOf(this);
    }
    // Bad debt
    function woe() public view returns (uint) {
        return sin.balanceOf(this);
    }
    // Collateral pending liquidation
    function fog() public view returns (uint) {
        return peth.balanceOf(this);
    }


    function DaiTap(DaiCdpContainer cdpContainer_) public {
        cdpContainer = cdpContainer_;

        dai = cdpContainer.dai();
        sin = cdpContainer.sin();
        peth = cdpContainer.peth();

        vox = cdpContainer.vox();

        wethToPethSpread18 = ONE_18;
    }

    function mold(bytes32 param, uint val) public note auth {
        if (param == 'wethToPethSpread18') wethToPethSpread18 = val;
    }

    // Cancel debt
    function heal() public note {
        if (joy() == 0 || woe() == 0) return;  // optimised
        var wad = min(joy(), woe());
        dai.burn(wad);
        sin.burn(wad);
    }

    // Feed price (dai per peth)
    function s2s() public returns (uint) {
        var tag = cdpContainer.usdPerPeth();    // ref per peth
        var par = vox.par();    // ref per dai
        return rdiv(tag, par);  // dai per peth
    }
    // Boom price (dai per peth)
    function bid(uint wad) public returns (uint) {
        return rmul(wad, wmul(s2s(), sub(2 * ONE_18, wethToPethSpread18)));
    }
    // Bust price (dai per peth)
    function ask(uint wad) public returns (uint) {
        return rmul(wad, wmul(s2s(), wethToPethSpread18));
    }
    function flip(uint wad) internal {
        require(ask(wad) > 0);
        peth.push(msg.sender, wad);
        dai.pull(msg.sender, ask(wad));
        heal();
    }
    function flop(uint wad) internal {
        peth.mint(sub(wad, fog()));
        flip(wad);
        require(joy() == 0);  // can't flop into surplus
    }
    function flap(uint wad) internal {
        heal();
        dai.push(msg.sender, bid(wad));
        peth.burn(msg.sender, wad);
    }
    function bust(uint wad) public note {
        require(!off);
        if (wad > fog()) flop(wad);
        else flip(wad);
    }
    function boom(uint wad) public note {
        require(!off);
        flap(wad);
    }

    //------------------------------------------------------------------

    function triggerGlobalSettlement(uint fix_) public note auth {
        require(!off);
        off = true;
        wethPerDaiAtSettlement = fix_;
    }
    function cash(uint wad) public note {
        require(off);
        dai.burn(msg.sender, wad);
        require(cdpContainer.weth().transfer(msg.sender, rmul(wad, wethPerDaiAtSettlement)));
    }
    function mock(uint wad) public note {
        require(off);
        dai.mint(msg.sender, wad);
        require(cdpContainer.weth().transferFrom(msg.sender, this, rmul(wad, wethPerDaiAtSettlement)));
    }
    function vent() public note {
        require(off);
        peth.burn(fog());
    }
}
