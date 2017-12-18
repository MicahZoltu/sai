/// mom.sol -- admin manager

// Copyright (C) 2017  Nikolai Mushegian <nikolai@dapphub.com>
// Copyright (C) 2017  Daniel Brockman <daniel@dapphub.com>
// Copyright (C) 2017  Rain <rainbreak@riseup.net>

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

import 'ds-thing/thing.sol';
import './cdpContainer.sol';
import './top.sol';
import './liquidator.sol';

contract DaiMom is DSThing {
    DaiCdpContainer  public  cdpContainer;
    DaiTap  public  liquidator;
    DaiVox  public  vox;

    function DaiMom(DaiCdpContainer cdpContainer_, DaiTap tap_, DaiVox vox_) public {
        cdpContainer = cdpContainer_;
        liquidator = tap_;
        vox = vox_;
    }
    // Debt ceiling
    function setCap(uint wad) public note auth {
        cdpContainer.mold("debtCeiling", wad);
    }
    // Liquidation ratio
    function setMat(uint ray) public note auth {
        cdpContainer.mold("liquidationRatio27", ray);
        var liquidationPenalty27 = cdpContainer.liquidationPenalty27();
        var liquidationRatio27 = cdpContainer.liquidationRatio27();
        require(liquidationPenalty27 >= ONE_27 && liquidationPenalty27 <= liquidationRatio27);
    }
    // Stability fee
    function setStabilityFee(uint ray) public note auth {
        cdpContainer.mold("stabilityFee27", ray);
        var stabilityFee27 = cdpContainer.stabilityFee27();
        require(ONE_27 <= stabilityFee27);
        require(stabilityFee27 < 1000001100000000000000000000);  // 10% / day
    }
    // Governance fee
    function setFee(uint ray) public note auth {
        cdpContainer.mold("governanceFee27", ray);
        var governanceFee27 = cdpContainer.governanceFee27();
        require(ONE_27 <= governanceFee27);
        require(governanceFee27 < 1000001100000000000000000000);  // 10% / day
    }
    // Liquidation fee
    function setAxe(uint ray) public note auth {
        cdpContainer.mold("liquidationPenalty27", ray);
        var liquidationPenalty27 = cdpContainer.liquidationPenalty27();
        var liquidationRatio27 = cdpContainer.liquidationRatio27();
        require(liquidationPenalty27 >= ONE_27 && liquidationPenalty27 <= liquidationRatio27);
    }
    // Join/Exit Spread
    function setCdpContainerGap(uint wad) public note auth {
        cdpContainer.mold("wethToPethSpread18", wad);
    }
    // ETH/USD Feed
    function setUsdPerEth(DSValue usdPerEth_) public note auth {
        cdpContainer.setUsdPerEth(usdPerEth_);
    }
    // MKR/USD Feed
    function setDaiPerMaker(DSValue daiPerMaker_) public note auth {
        cdpContainer.setDaiPerMaker(daiPerMaker_);
    }
    // TRFM
    function setVox(DaiVox vox_) public note auth {
        cdpContainer.setVox(vox_);
    }
    // Boom/Bust Spread
    function setTapGap(uint wad) public note auth {
        liquidator.mold("wethToPethSpread18", wad);
        var wethToPethSpread18 = liquidator.wethToPethSpread18();
        require(wethToPethSpread18 <= 1.05 ether);
        require(wethToPethSpread18 >= 0.95 ether);
    }
    // Rate of change of target price (per second)
    function setWay(uint ray) public note auth {
        require(ray < 1000001100000000000000000000);  // 10% / day
        require(ray >  999998800000000000000000000);
        vox.mold("way", ray);
    }
    function setHow(uint ray) public note auth {
        vox.tune(ray);
    }
}
