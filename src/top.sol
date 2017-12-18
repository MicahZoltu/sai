/// top.sol -- global settlement manager

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
import "./liquidator.sol";

contract DaiTop is DSThing {
    DaiVox   public  vox;
    DaiCdpContainer   public  cdpContainer;
    DaiTap   public  liquidator;

    DSToken  public  dai;
    DSToken  public  sin;
    DSToken  public  peth;
    ERC20    public  weth;

    uint256  public  wethPerDaiAtSettlement;  // dai triggerGlobalSettlement price (weth per dai)
    uint256  public  usdPerPethAtSettlement;  // peth triggerGlobalSettlement price (ref per peth)
    uint256  public  caged;
    uint256  public  cooldown = 6 hours;

    function DaiTop(DaiCdpContainer cdpContainer_, DaiTap tap_) public {
        cdpContainer = cdpContainer_;
        liquidator = tap_;

        vox = cdpContainer.vox();

        dai = cdpContainer.dai();
        sin = cdpContainer.sin();
        peth = cdpContainer.peth();
        weth = cdpContainer.weth();
    }

    function getCurrentTimestamp() public view returns (uint) {
        return block.timestamp;
    }

    // force settlement of the system at a given price (dai per weth).
    // This is nearly the equivalent of biting all cdps at once.
    // Important consideration: the weths associated with free peth can
    // be tapped to make dai whole.
    function triggerGlobalSettlement(uint price) internal {
        require(!cdpContainer.off() && price != 0);
        caged = getCurrentTimestamp();

        cdpContainer.drip();  // collect remaining fees
        liquidator.heal();  // absorb any pending fees

        usdPerPethAtSettlement = rmul(wmul(price, vox.par()), cdpContainer.wethPerPeth());
        // Most weths we can get per dai is the full balance of the cdpContainer.
        // If there is no dai issued, we should still be able to triggerGlobalSettlement.
        if (dai.totalSupply() == 0) {
            wethPerDaiAtSettlement = rdiv(ONE_18, price);
        } else {
            wethPerDaiAtSettlement = min(rdiv(ONE_18, price), rdiv(cdpContainer.wethLockedInPeth(), dai.totalSupply()));
        }

        cdpContainer.triggerGlobalSettlement(usdPerPethAtSettlement, rmul(wethPerDaiAtSettlement, dai.totalSupply()));
        liquidator.triggerGlobalSettlement(wethPerDaiAtSettlement);

        liquidator.vent();    // burn pending sale peth
    }
    // triggerGlobalSettlement by reading the last value from the feed for the price
    function triggerGlobalSettlement() public note auth {
        triggerGlobalSettlement(rdiv(uint(cdpContainer.usdPerEth().read()), vox.par()));
    }

    function flow() public note {
        require(cdpContainer.off());
        var empty = cdpContainer.din() == 0 && liquidator.fog() == 0;
        var ended = getCurrentTimestamp() > caged + cooldown;
        require(empty || ended);
        cdpContainer.flow();
    }

    function setCooldown(uint cooldown_) public auth {
        cooldown = cooldown_;
    }
}
