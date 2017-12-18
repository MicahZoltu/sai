pragma solidity ^0.4.18;

import "ds-auth/auth.sol";
import 'ds-token/token.sol';
import 'ds-guard/guard.sol';
import 'ds-roles/roles.sol';
import 'ds-value/value.sol';

import './mom.sol';

contract WethFactory {
    function newTok(bytes32 name) public returns (DSToken token) {
        token = new DSToken(name);
        token.setOwner(msg.sender);
    }
}

contract VoxFactory {
    function newVox() public returns (DaiVox vox) {
        vox = new DaiVox(10 ** 27);
        vox.setOwner(msg.sender);
    }
}

contract CdpContainerFactory {
    function newCdpContainer(DSToken dai, DSToken sin, DSToken peth, ERC20 weth, DSToken mkr, DSValue usdPerEth, DSValue daiPerMaker, DaiVox vox, address pit) public returns (DaiCdpContainer cdpContainer) {
        cdpContainer = new DaiCdpContainer(dai, sin, peth, weth, mkr, usdPerEth, daiPerMaker, vox, pit);
        cdpContainer.setOwner(msg.sender);
    }
}

contract LiquidatorFactory {
    function newTap(DaiCdpContainer cdpContainer) public returns (DaiTap liquidator) {
        liquidator = new DaiTap(cdpContainer);
        liquidator.setOwner(msg.sender);
    }
}

contract TopFactory {
    function newTop(DaiCdpContainer cdpContainer, DaiTap liquidator) public returns (DaiTop top) {
        top = new DaiTop(cdpContainer, liquidator);
        top.setOwner(msg.sender);
    }
}

contract MomFactory {
    function newMom(DaiCdpContainer cdpContainer, DaiTap liquidator, DaiVox vox) public returns (DaiMom mom) {
        mom = new DaiMom(cdpContainer, liquidator, vox);
        mom.setOwner(msg.sender);
    }
}

contract DadFactory {
    function newDad() public returns (DSGuard dad) {
        dad = new DSGuard();
        dad.setOwner(msg.sender);
    }
}

contract DaiFactory is DSAuth {
    WethFactory public wethFactory;
    VoxFactory public voxFactory;
    LiquidatorFactory public liquidatorFactory;
    CdpContainerFactory public cdpContainerFactory;
    TopFactory public topFactory;
    MomFactory public momFactory;
    DadFactory public dadFactory;

    DSToken public dai;
    DSToken public sin;
    DSToken public peth;

    DaiVox public vox;
    DaiCdpContainer public cdpContainer;
    DaiTap public liquidator;
    DaiTop public top;

    DaiMom public mom;
    DSGuard public dad;

    uint8 public step = 0;

    function DaiFactory(WethFactory wethFactory_, VoxFactory voxFactory_, CdpContainerFactory cdpContainerFactory_, LiquidatorFactory tapFactory_, TopFactory topFactory_, MomFactory momFactory_, DadFactory dadFactory_) public {
        wethFactory = wethFactory_;
        voxFactory = voxFactory_;
        cdpContainerFactory = cdpContainerFactory_;
        liquidatorFactory = tapFactory_;
        topFactory = topFactory_;
        momFactory = momFactory_;
        dadFactory = dadFactory_;
    }

    function makeTokens() public auth {
        require(step == 0);
        dai = wethFactory.newTok('DAI');
        sin = wethFactory.newTok('SIN');
        peth = wethFactory.newTok('PETH');
        step += 1;
    }

    function makeVoxCdpContainer(ERC20 weth, DSToken mkr, DSValue usdPerEth, DSValue daiPerMaker, address pit) public auth {
        require(step == 1);
        require(address(weth) != 0x0);
        require(address(mkr) != 0x0);
        require(address(usdPerEth) != 0x0);
        require(address(daiPerMaker) != 0x0);
        require(pit != 0x0);
        vox = voxFactory.newVox();
        cdpContainer = cdpContainerFactory.newCdpContainer(dai, sin, peth, weth, mkr, usdPerEth, daiPerMaker, vox, pit);
        step += 1;
    }

    function makeTapTop() public auth {
        require(step == 2);
        liquidator = liquidatorFactory.newTap(cdpContainer);
        cdpContainer.turn(liquidator);
        top = topFactory.newTop(cdpContainer, liquidator);
        step += 1;
    }

    function S(string s) internal pure returns (bytes4) {
        return bytes4(keccak256(s));
    }

    function ray(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 9;
    }

    // Liquidation Ratio   150%
    // Liquidation Penalty 13%
    // Stability Fee       0.05%
    // PETH Fee            0%
    // Boom/Bust Spread   -3%
    // Join/Exit Spread    0%
    // Debt Ceiling        0
    function configParams() public auth {
        require(step == 3);

        cdpContainer.mold("debtCeiling", 0);
        cdpContainer.mold("liquidationRatio27", ray(1.5  ether));
        cdpContainer.mold("liquidationPenalty27", ray(1.13 ether));
        cdpContainer.mold("governanceFee27", 1000000000158153903837946257);  // 0.5% / year
        cdpContainer.mold("stabilityFee27", ray(1 ether));
        cdpContainer.mold("wethToPethSpread18", 1 ether);

        liquidator.mold("wethToPethSpread18", 0.97 ether);

        step += 1;
    }

    function verifyParams() public auth {
        require(step == 4);

        require(cdpContainer.debtCeiling() == 0);
        require(cdpContainer.liquidationRatio27() == 1500000000000000000000000000);
        require(cdpContainer.liquidationPenalty27() == 1130000000000000000000000000);
        require(cdpContainer.governanceFee27() == 1000000000158153903837946257);
        require(cdpContainer.stabilityFee27() == 1000000000000000000000000000);
        require(cdpContainer.wethToPethSpread18() == 1000000000000000000);

        require(liquidator.wethToPethSpread18() == 970000000000000000);

        require(vox.par() == 1000000000000000000000000000);
        require(vox.how() == 0);

        step += 1;
    }

    function configAuth(DSAuthority authority) public auth {
        require(step == 5);
        require(address(authority) != 0x0);

        mom = momFactory.newMom(cdpContainer, liquidator, vox);
        dad = dadFactory.newDad();

        vox.setAuthority(dad);
        vox.setOwner(0);
        cdpContainer.setAuthority(dad);
        cdpContainer.setOwner(0);
        liquidator.setAuthority(dad);
        liquidator.setOwner(0);
        dai.setAuthority(dad);
        dai.setOwner(0);
        sin.setAuthority(dad);
        sin.setOwner(0);
        peth.setAuthority(dad);
        peth.setOwner(0);

        top.setAuthority(authority);
        top.setOwner(0);
        mom.setAuthority(authority);
        mom.setOwner(0);

        dad.permit(top, cdpContainer, S("triggerGlobalSettlement(uint256,uint256)"));
        dad.permit(top, cdpContainer, S("flow()"));
        dad.permit(top, liquidator, S("triggerGlobalSettlement(uint256)"));

        dad.permit(cdpContainer, peth, S('mint(address,uint256)'));
        dad.permit(cdpContainer, peth, S('burn(address,uint256)'));

        dad.permit(cdpContainer, dai, S('mint(address,uint256)'));
        dad.permit(cdpContainer, dai, S('burn(address,uint256)'));

        dad.permit(cdpContainer, sin, S('mint(address,uint256)'));

        dad.permit(liquidator, dai, S('mint(address,uint256)'));
        dad.permit(liquidator, dai, S('burn(address,uint256)'));
        dad.permit(liquidator, dai, S('burn(uint256)'));
        dad.permit(liquidator, sin, S('burn(uint256)'));

        dad.permit(liquidator, peth, S('mint(uint256)'));
        dad.permit(liquidator, peth, S('burn(uint256)'));
        dad.permit(liquidator, peth, S('burn(address,uint256)'));

        dad.permit(mom, vox, S("mold(bytes32,uint256)"));
        dad.permit(mom, vox, S("tune(uint256)"));
        dad.permit(mom, cdpContainer, S("mold(bytes32,uint256)"));
        dad.permit(mom, liquidator, S("mold(bytes32,uint256)"));
        dad.permit(mom, cdpContainer, S("setUsdPerEth(address)"));
        dad.permit(mom, cdpContainer, S("setDaiPerMaker(address)"));
        dad.permit(mom, cdpContainer, S("setVox(address)"));

        dad.setOwner(0);
        step += 1;
    }
}
