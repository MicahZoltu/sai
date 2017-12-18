pragma solidity ^0.4.18;

import "ds-test/test.sol";

import "ds-math/math.sol";

import 'ds-token/token.sol';
import 'ds-roles/roles.sol';
import 'ds-value/value.sol';

import './weth9.sol';
import './mom.sol';
import './factory.sol';
import './pit.sol';

contract TestWarp is DSNote {
    uint256  _era;

    function TestWarp() public {
        _era = now;
    }

    function getCurrentTimestamp() public view returns (uint256) {
        return _era == 0 ? now : _era;
    }

    function warp(uint age) public note {
        require(_era != 0);
        _era = age == 0 ? 0 : _era + age;
    }
}

contract DevCdpContainer is DaiCdpContainer, TestWarp {
    function DevCdpContainer(
        DSToken  dai_,
        DSToken  sin_,
        DSToken  peth_,
        ERC20    weth_,
        DSToken  mkr_,
        DSValue  usdPerEth_,
        DSValue  daiPerMaker_,
        DaiVox   vox_,
        address  pit_
    ) public
      DaiCdpContainer(dai_, sin_, peth_, weth_, mkr_, usdPerEth_, daiPerMaker_, vox_, pit_) {}
}

contract DevTop is DaiTop, TestWarp {
    function DevTop(DaiCdpContainer cdpContainer_, DaiTap tap_) public DaiTop(cdpContainer_, tap_) {}
}

contract DevVox is DaiVox, TestWarp {
    function DevVox(uint par_) DaiVox(par_) public {}
}

contract DevVoxFactory {
    function newVox() public returns (DevVox vox) {
        vox = new DevVox(10 ** 27);
        vox.setOwner(msg.sender);
    }
}

contract DevCdpContainerFactory {
    function newCdpContainer(DSToken dai, DSToken sin, DSToken peth, DSToken weth, DSToken mkr, DSValue usdPerEth, DSValue daiPerMaker, DaiVox vox, address pit) public returns (DevCdpContainer cdpContainer) {
        cdpContainer = new DevCdpContainer(dai, sin, peth, weth, mkr, usdPerEth, daiPerMaker, vox, pit);
        cdpContainer.setOwner(msg.sender);
    }
}

contract DevTopFactory {
    function newTop(DevCdpContainer cdpContainer, DaiTap liquidator) public returns (DevTop top) {
        top = new DevTop(cdpContainer, liquidator);
        top.setOwner(msg.sender);
    }
}

contract DevDadFactory {
    function newDad() public returns (DSGuard dad) {
        dad = new DSGuard();
        // convenience in tests
        dad.permit(DaiFactory(msg.sender).getOwner(), DaiFactory(msg.sender).dai(), bytes4(keccak256('mint(uint256)')));
        dad.permit(DaiFactory(msg.sender).getOwner(), DaiFactory(msg.sender).dai(), bytes4(keccak256('burn(uint256)')));
        dad.permit(DaiFactory(msg.sender).getOwner(), DaiFactory(msg.sender).dai(), bytes4(keccak256('mint(address,uint256)')));
        dad.permit(DaiFactory(msg.sender).getOwner(), DaiFactory(msg.sender).dai(), bytes4(keccak256('burn(address,uint256)')));
        dad.permit(DaiFactory(msg.sender).getOwner(), DaiFactory(msg.sender).sin(), bytes4(keccak256('mint(uint256)')));
        dad.permit(DaiFactory(msg.sender).getOwner(), DaiFactory(msg.sender).sin(), bytes4(keccak256('burn(uint256)')));
        dad.permit(DaiFactory(msg.sender).getOwner(), DaiFactory(msg.sender).sin(), bytes4(keccak256('mint(address,uint256)')));
        dad.permit(DaiFactory(msg.sender).getOwner(), DaiFactory(msg.sender).sin(), bytes4(keccak256('burn(address,uint256)')));
        dad.permit(DaiFactory(msg.sender).getOwner(), DaiFactory(msg.sender).peth(), bytes4(keccak256('mint(uint256)')));
        dad.permit(DaiFactory(msg.sender).getOwner(), DaiFactory(msg.sender).peth(), bytes4(keccak256('burn(uint256)')));
        dad.permit(DaiFactory(msg.sender).getOwner(), DaiFactory(msg.sender).peth(), bytes4(keccak256('mint(address,uint256)')));
        dad.permit(DaiFactory(msg.sender).getOwner(), DaiFactory(msg.sender).peth(), bytes4(keccak256('burn(address,uint256)')));
        dad.setOwner(msg.sender);
    }
}

contract FakePerson {
    DaiTap  public liquidator;
    DSToken public dai;

    function FakePerson(DaiTap _tap) public {
        liquidator = _tap;
        dai = liquidator.dai();
        dai.approve(liquidator);
    }

    function cash() public {
        liquidator.cash(dai.balanceOf(this));
    }
}

contract DaiTestBase is DSTest, DSMath {
    DevVox   vox;
    DevCdpContainer   cdpContainer;
    DevTop   top;
    DaiTap   liquidator;

    DaiMom   mom;

    WETH9    weth;
    DSToken  dai;
    DSToken  sin;
    DSToken  peth;
    DSToken  mkr;

    WethPit   pit;

    DSValue  usdPerEth;
    DSValue  daiPerMaker;
    DSRoles  dad;

    function ray(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 9;
    }
    function wad(uint256 ray_) internal pure returns (uint256) {
        return wdiv(ray_, ONE_27);
    }

    function mark(uint price) internal {
        usdPerEth.poke(bytes32(price));
    }
    function mark(DSToken tkn, uint price) internal {
        if (address(tkn) == address(mkr)) daiPerMaker.poke(bytes32(price));
        else if (address(tkn) == address(weth)) mark(price);
    }
    function warp(uint256 age) internal {
        vox.warp(age);
        cdpContainer.warp(age);
        top.warp(age);
    }

    function setUp() public {
        WethFactory wethFactory = new WethFactory();
        DevVoxFactory voxFactory = new DevVoxFactory();
        DevCdpContainerFactory cdpContainerFactory = new DevCdpContainerFactory();
        LiquidatorFactory liquidatorFactory = new LiquidatorFactory();
        DevTopFactory topFactory = new DevTopFactory();
        MomFactory momFactory = new MomFactory();
        DevDadFactory dadFactory = new DevDadFactory();

        DaiFactory daiFactory = new DaiFactory(wethFactory, VoxFactory(voxFactory), CdpContainerFactory(cdpContainerFactory), liquidatorFactory, TopFactory(topFactory), momFactory, DadFactory(dadFactory));

        weth = new WETH9();
        weth.deposit.value(100 ether)();
        mkr = new DSToken('MKR');
        usdPerEth = new DSValue();
        daiPerMaker = new DSValue();
        pit = new WethPit();

        daiFactory.makeTokens();
        daiFactory.makeVoxCdpContainer(ERC20(weth), mkr, usdPerEth, daiPerMaker, pit);
        daiFactory.makeTapTop();
        daiFactory.configParams();
        daiFactory.verifyParams();
        DSRoles authority = new DSRoles();
        authority.setRootUser(this, true);
        daiFactory.configAuth(authority);

        dai = DSToken(daiFactory.dai());
        sin = DSToken(daiFactory.sin());
        peth = DSToken(daiFactory.peth());
        vox = DevVox(daiFactory.vox());
        cdpContainer = DevCdpContainer(daiFactory.cdpContainer());
        liquidator = DaiTap(daiFactory.liquidator());
        top = DevTop(daiFactory.top());
        mom = DaiMom(daiFactory.mom());
        dad = DSRoles(daiFactory.dad());

        dai.approve(cdpContainer);
        peth.approve(cdpContainer);
        weth.approve(cdpContainer, uint(-1));
        mkr.approve(cdpContainer);

        dai.approve(liquidator);
        peth.approve(liquidator);

        mark(1 ether);
        mark(mkr, 1 ether);

        mom.setCap(20 ether);
        mom.setAxe(ray(1 ether));
        mom.setMat(ray(1 ether));
        mom.setStabilityFee(ray(1 ether));
        mom.setFee(ray(1 ether));
        mom.setCdpContainerGap(1 ether);
        mom.setTapGap(1 ether);
    }
}

contract DaiCdpContainerTest is DaiTestBase {
    function testBasic() public {
        assertEq( peth.balanceOf(cdpContainer), 0 ether );
        assertEq( peth.balanceOf(this), 0 ether );
        assertEq( weth.balanceOf(cdpContainer), 0 ether );

        // edge case
        assertEq( uint256(cdpContainer.wethPerPeth()), ray(1 ether) );
        cdpContainer.buyPethWithWeth(10 ether);
        assertEq( uint256(cdpContainer.wethPerPeth()), ray(1 ether) );

        assertEq( peth.balanceOf(this), 10 ether );
        assertEq( weth.balanceOf(cdpContainer), 10 ether );
        // price formula
        cdpContainer.buyPethWithWeth(10 ether);
        assertEq( uint256(cdpContainer.wethPerPeth()), ray(1 ether) );
        assertEq( peth.balanceOf(this), 20 ether );
        assertEq( weth.balanceOf(cdpContainer), 20 ether );

        var cdp = cdpContainer.open();

        assertEq( peth.balanceOf(this), 20 ether );
        assertEq( peth.balanceOf(cdpContainer), 0 ether );
        cdpContainer.depositPeth(cdp, 10 ether); // lock peth token
        assertEq( peth.balanceOf(this), 10 ether );
        assertEq( peth.balanceOf(cdpContainer), 10 ether );

        assertEq( dai.balanceOf(this), 0 ether);
        cdpContainer.withdrawDai(cdp, 5 ether);
        assertEq( dai.balanceOf(this), 5 ether);


        assertEq( dai.balanceOf(this), 5 ether);
        cdpContainer.depositDai(cdp, 2 ether);
        assertEq( dai.balanceOf(this), 3 ether);

        assertEq( dai.balanceOf(this), 3 ether);
        assertEq( peth.balanceOf(this), 10 ether );
        cdpContainer.shut(cdp);
        assertEq( dai.balanceOf(this), 0 ether);
        assertEq( peth.balanceOf(this), 20 ether );
    }
    function testGive() public {
        var cdp = cdpContainer.open();
        assertEq(cdpContainer.getOwner(cdp), this);

        address ali = 0x456;
        transferOwnership(cdp, ali);
        assertEq(cdpContainer.getOwner(cdp), ali);
    }
    function testFailGiveNotOwner() public {
        var cdp = cdpContainer.open();
        address ali = 0x456;
        transferOwnership(cdp, ali);

        address bob = 0x789;
        transferOwnership(cdp, bob);
    }
    function testMold() public {
        var setAxe = bytes4(keccak256('setAxe(uint256)'));
        var setCap = bytes4(keccak256('setCap(uint256)'));
        var setMat = bytes4(keccak256('setMat(uint256)'));

        assertTrue(mom.call(setCap, 0 ether));
        assertTrue(mom.call(setCap, 5 ether));

        assertTrue(!mom.call(setAxe, ray(2 ether)));
        assertTrue( mom.call(setMat, ray(2 ether)));
        assertTrue( mom.call(setAxe, ray(2 ether)));
        assertTrue(!mom.call(setMat, ray(1 ether)));
    }
    function testTune() public {
        assertEq(vox.how(), 0);
        mom.setHow(2 * 10 ** 25);
        assertEq(vox.how(), 2 * 10 ** 25);
    }
    function testPriceFeedSetters() public {
        var setUsdPerEth = bytes4(keccak256('setUsdPerEth(address)'));
        var setDaiPerMaker = bytes4(keccak256('setDaiPerMaker(address)'));
        var setVox = bytes4(keccak256('setVox(address)'));

        assertTrue(cdpContainer.usdPerEth() != address(0x1));
        assertTrue(cdpContainer.daiPerMaker() != address(0x2));
        assertTrue(cdpContainer.vox() != address(0x3));
        assertTrue(mom.call(setUsdPerEth, address(0x1)));
        assertTrue(mom.call(setDaiPerMaker, address(0x2)));
        assertTrue(mom.call(setVox, address(0x3)));
        assertTrue(cdpContainer.usdPerEth() == address(0x1));
        assertTrue(cdpContainer.daiPerMaker() == address(0x2));
        assertTrue(cdpContainer.vox() == address(0x3));
    }
    function testJoinInitial() public {
        assertEq(peth.totalSupply(),     0 ether);
        assertEq(peth.balanceOf(this),   0 ether);
        assertEq(weth.balanceOf(this), 100 ether);
        cdpContainer.buyPethWithWeth(10 ether);
        assertEq(peth.balanceOf(this), 10 ether);
        assertEq(weth.balanceOf(this), 90 ether);
        assertEq(weth.balanceOf(cdpContainer),  10 ether);
    }
    function testJoinExit() public {
        assertEq(peth.balanceOf(this), 0 ether);
        assertEq(weth.balanceOf(this), 100 ether);
        cdpContainer.buyPethWithWeth(10 ether);
        assertEq(peth.balanceOf(this), 10 ether);
        assertEq(weth.balanceOf(this), 90 ether);
        assertEq(weth.balanceOf(cdpContainer),  10 ether);

        cdpContainer.sellPethForWeth(5 ether);
        assertEq(peth.balanceOf(this),  5 ether);
        assertEq(weth.balanceOf(this), 95 ether);
        assertEq(weth.balanceOf(cdpContainer),   5 ether);

        cdpContainer.buyPethWithWeth(2 ether);
        assertEq(peth.balanceOf(this),  7 ether);
        assertEq(weth.balanceOf(this), 93 ether);
        assertEq(weth.balanceOf(cdpContainer),   7 ether);

        cdpContainer.sellPethForWeth(1 ether);
        assertEq(peth.balanceOf(this),  6 ether);
        assertEq(weth.balanceOf(this), 94 ether);
        assertEq(weth.balanceOf(cdpContainer),   6 ether);
    }
    function testFailOverDraw() public {
        mom.setMat(ray(1 ether));
        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);

        cdpContainer.withdrawDai(cdp, 11 ether);
    }
    function testFailOverDrawExcess() public {
        mom.setMat(ray(1 ether));
        cdpContainer.buyPethWithWeth(20 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);

        cdpContainer.withdrawDai(cdp, 11 ether);
    }
    function testDraw() public {
        mom.setMat(ray(1 ether));
        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);

        assertEq(dai.balanceOf(this),  0 ether);
        cdpContainer.withdrawDai(cdp, 10 ether);
        assertEq(dai.balanceOf(this), 10 ether);
    }
    function testWipe() public {
        mom.setMat(ray(1 ether));
        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);
        cdpContainer.withdrawDai(cdp, 10 ether);

        assertEq(dai.balanceOf(this), 10 ether);
        cdpContainer.depositDai(cdp, 5 ether);
        assertEq(dai.balanceOf(this),  5 ether);
    }
    function testUnisAboveMarginCallThreshold() public {
        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);
        cdpContainer.withdrawDai(cdp, 9 ether);

        assertTrue(cdpContainer.isAboveMarginCallThreshold(cdp));
        mark(1 ether / 2);
        assertTrue(!cdpContainer.isAboveMarginCallThreshold(cdp));
    }
    function testBiteUnderParity() public {
        assertEq(uint(cdpContainer.liquidationPenalty27()), uint(ray(1 ether)));  // 100% collateralisation limit
        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);
        cdpContainer.withdrawDai(cdp, 5 ether);           // 200% collateralisation
        mark(1 ether / 4);                // 50% collateralisation

        assertEq(liquidator.fog(), uint(0));
        cdpContainer.marginCall(cdp);
        assertEq(liquidator.fog(), uint(10 ether));
    }
    function testBiteOverParity() public {
        mom.setMat(ray(2 ether));  // require 200% collateralisation
        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);

        cdpContainer.withdrawDai(cdp, 4 ether);  // 250% collateralisation
        assertTrue(cdpContainer.isAboveMarginCallThreshold(cdp));
        mark(1 ether / 2);       // 125% collateralisation
        assertTrue(!cdpContainer.isAboveMarginCallThreshold(cdp));

        assertEq(cdpContainer.din(),    4 ether);
        assertEq(cdpContainer.tab(cdp), 4 ether);
        assertEq(liquidator.fog(),    0 ether);
        assertEq(liquidator.woe(),    0 ether);
        cdpContainer.marginCall(cdp);
        assertEq(cdpContainer.din(),    0 ether);
        assertEq(cdpContainer.tab(cdp), 0 ether);
        assertEq(liquidator.fog(),    8 ether);
        assertEq(liquidator.woe(),    4 ether);

        // cdp should now be safe with 0 dai debt and 2 peth remaining
        var peth_before = peth.balanceOf(this);
        cdpContainer.withdrawPeth(cdp, 1 ether);
        assertEq(peth.balanceOf(this) - peth_before, 1 ether);
    }
    function testLock() public {
        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();

        assertEq(peth.balanceOf(cdpContainer),  0 ether);
        cdpContainer.depositPeth(cdp, 10 ether);
        assertEq(peth.balanceOf(cdpContainer), 10 ether);
    }
    function testFree() public {
        mom.setMat(ray(2 ether));  // require 200% collateralisation
        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);
        cdpContainer.withdrawDai(cdp, 4 ether);  // 250% collateralisation

        var peth_before = peth.balanceOf(this);
        cdpContainer.withdrawPeth(cdp, 2 ether);  // 225%
        assertEq(peth.balanceOf(this) - peth_before, 2 ether);
    }
    function testFailFreeToUnderCollat() public {
        mom.setMat(ray(2 ether));  // require 200% collateralisation
        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);
        cdpContainer.withdrawDai(cdp, 4 ether);  // 250% collateralisation

        cdpContainer.withdrawPeth(cdp, 3 ether);  // 175% -- fails
    }
    function testFailDrawOverDebtCeiling() public {
        mom.setCap(4 ether);
        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);

        cdpContainer.withdrawDai(cdp, 5 ether);
    }
    function testDebtCeiling() public {
        mom.setCap(5 ether);
        mom.setMat(ray(2 ether));  // require 200% collat
        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);

        cdpContainer.withdrawDai(cdp, 5 ether);          // 200% collat, full debt ceiling
        mark(1 ether / 2);  // 100% collat

        assertEq(cdpContainer.totalCollateralizedPeth(), uint(10 ether));
        assertEq(liquidator.fog(), uint(0 ether));
        cdpContainer.marginCall(cdp);
        assertEq(cdpContainer.totalCollateralizedPeth(), uint(0 ether));
        assertEq(liquidator.fog(), uint(10 ether));

        cdpContainer.buyPethWithWeth(10 ether);
        // peth hasn't been diluted yet so still 1:1 peth:weth
        assertEq(peth.balanceOf(this), 10 ether);
    }
}

contract CageTest is DaiTestBase {
    // ensure triggerGlobalSettlement sets the settle prices right
    function cageSetup() public returns (bytes32) {
        mom.setCap(5 ether);            // 5 dai debt ceiling
        mark(1 ether);   // price 1:1 weth:ref
        mom.setMat(ray(2 ether));       // require 200% collat
        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);
        cdpContainer.withdrawDai(cdp, 5 ether);       // 200% collateralisation

        return cdp;
    }
    function testCageSafeOverCollat() public {
        cageSetup();

        assertEq(top.wethPerDaiAtSettlement(), 0);
        assertEq(cdpContainer.usdPerPethAtSettlement(), 0);
        assertEq(liquidator.woe(), 0);         // no bad debt
        assertEq(cdpContainer.wethLockedInPeth(), 10 ether);

        cdpContainer.buyPethWithWeth(20 ether);   // give us some more peth
        mark(1 ether);
        top.triggerGlobalSettlement();

        assertEq(cdpContainer.din(),      5 ether);  // debt remains in cdpContainer
        assertEq(wad(top.wethPerDaiAtSettlement()), 1 ether);  // dai redeems 1:1 with weth
        assertEq(wad(cdpContainer.usdPerPethAtSettlement()), 1 ether);  // peth redeems 1:1 with weth just before pushing weth to cdpContainer

        assertEq(weth.balanceOf(liquidator),  5 ether);  // saved for dai
        assertEq(weth.balanceOf(cdpContainer), 25 ether);  // saved for peth
    }
    function testCageUnsafeOverCollat() public {
        cageSetup();

        assertEq(top.wethPerDaiAtSettlement(), 0);
        assertEq(cdpContainer.usdPerPethAtSettlement(), 0);
        assertEq(cdpContainer.wethPerPeth(), ray(1 ether));

        cdpContainer.buyPethWithWeth(20 ether);   // give us some more peth
        var price = wdiv(3 ether, 4 ether);
        mark(price);
        top.triggerGlobalSettlement();        // 150% collat

        assertEq(top.wethPerDaiAtSettlement(), rdiv(1 ether, price));  // dai redeems 4:3 with weth
        assertEq(cdpContainer.usdPerPethAtSettlement(), ray(price));                 // peth redeems 1:1 with weth just before pushing weth to cdpContainer

        // weth needed for dai is 5 * 4 / 3
        var saved = rmul(5 ether, rdiv(ONE_18, price));
        assertEq(weth.balanceOf(liquidator),  saved);             // saved for dai
        assertEq(weth.balanceOf(cdpContainer),  30 ether - saved);  // saved for peth
    }
    function testCageAtCollat() public {
        cageSetup();

        assertEq(top.wethPerDaiAtSettlement(), 0);
        assertEq(cdpContainer.usdPerPethAtSettlement(), 0);
        assertEq(cdpContainer.wethPerPeth(), ray(1 ether));

        var price = wdiv(1 ether, 2 ether);  // 100% collat
        mark(price);
        top.triggerGlobalSettlement();

        assertEq(top.wethPerDaiAtSettlement(), ray(2 ether));  // dai redeems 1:2 with weth, 1:1 with ref
        assertEq(cdpContainer.wethPerPeth(), 0);       // peth redeems 1:0 with weth after triggerGlobalSettlement
    }
    function testCageAtCollatFreePeth() public {
        cageSetup();

        assertEq(top.wethPerDaiAtSettlement(), 0);
        assertEq(cdpContainer.usdPerPethAtSettlement(), 0);
        assertEq(cdpContainer.wethPerPeth(), ray(1 ether));

        cdpContainer.buyPethWithWeth(20 ether);   // give us some more peth
        var price = wdiv(1 ether, 2 ether);  // 100% collat
        mark(price);
        top.triggerGlobalSettlement();

        assertEq(top.wethPerDaiAtSettlement(), ray(2 ether));  // dai redeems 1:2 with weth, 1:1 with ref
        assertEq(cdpContainer.usdPerPethAtSettlement(), ray(price));       // peth redeems 1:1 with weth just before pushing weth to cdpContainer
    }
    function testCageUnderCollat() public {
        cageSetup();

        assertEq(top.wethPerDaiAtSettlement(), 0);
        assertEq(cdpContainer.usdPerPethAtSettlement(), 0);
        assertEq(cdpContainer.wethPerPeth(), ray(1 ether));

        var price = wdiv(1 ether, 4 ether);   // 50% collat
        mark(price);
        top.triggerGlobalSettlement();

        assertEq(2 * dai.totalSupply(), weth.balanceOf(liquidator));
        assertEq(top.wethPerDaiAtSettlement(), ray(2 ether));  // dai redeems 1:2 with weth, 2:1 with ref
        assertEq(cdpContainer.wethPerPeth(), 0);       // peth redeems 1:0 with weth after triggerGlobalSettlement
    }
    function testCageUnderCollatFreePeth() public {
        cageSetup();

        assertEq(top.wethPerDaiAtSettlement(), 0);
        assertEq(cdpContainer.usdPerPethAtSettlement(), 0);
        assertEq(cdpContainer.wethPerPeth(), ray(1 ether));

        cdpContainer.buyPethWithWeth(20 ether);   // give us some more peth
        var price = wdiv(1 ether, 4 ether);   // 50% collat
        mark(price);
        top.triggerGlobalSettlement();

        assertEq(4 * dai.totalSupply(), weth.balanceOf(liquidator));
        assertEq(top.wethPerDaiAtSettlement(), ray(4 ether));                 // dai redeems 1:4 with weth, 1:1 with ref
    }

    function testCageNoDai() public {
        var cdp = cageSetup();
        cdpContainer.depositDai(cdp, 5 ether);
        assertEq(dai.totalSupply(), 0);

        top.triggerGlobalSettlement();
        assertEq(top.wethPerDaiAtSettlement(), ray(1 ether));
    }
    function testMock() public {
        cageSetup();
        top.triggerGlobalSettlement();

        weth.deposit.value(1000 ether)();
        weth.approve(liquidator, uint(-1));
        liquidator.mock(1000 ether);
        assertEq(dai.balanceOf(this), 1005 ether);
        assertEq(weth.balanceOf(liquidator),  1005 ether);
    }
    function testMockNoDai() public {
        var cdp = cageSetup();
        cdpContainer.depositDai(cdp, 5 ether);
        assertEq(dai.totalSupply(), 0);

        top.triggerGlobalSettlement();

        weth.deposit.value(1000 ether)();
        weth.approve(liquidator, uint(-1));
        liquidator.mock(1000 ether);
        assertEq(dai.balanceOf(this), 1000 ether);
        assertEq(weth.balanceOf(liquidator),  1000 ether);
    }

    // ensure cash returns the expected amount
    function testCashSafeOverCollat() public {
        var cdp = cageSetup();
        mark(1 ether);
        top.triggerGlobalSettlement();

        assertEq(dai.balanceOf(this),  5 ether);
        assertEq(peth.balanceOf(this),  0 ether);
        assertEq(weth.balanceOf(this), 90 ether);
        assertEq(weth.balanceOf(cdpContainer),   5 ether);
        assertEq(weth.balanceOf(liquidator),   5 ether);

        liquidator.cash(dai.balanceOf(this));
        assertEq(dai.balanceOf(this),   0 ether);
        assertEq(peth.balanceOf(this),   0 ether);
        assertEq(weth.balanceOf(this),  95 ether);
        assertEq(weth.balanceOf(cdpContainer),    5 ether);

        assertEq(cdpContainer.getPethCollateral(cdp), 10 ether);
        cdpContainer.marginCall(cdp);
        assertEq(cdpContainer.getPethCollateral(cdp), 5 ether);
        cdpContainer.withdrawPeth(cdp, cdpContainer.getPethCollateral(cdp));
        assertEq(peth.balanceOf(this),   5 ether);
        liquidator.vent();
        top.flow();
        cdpContainer.sellPethForWeth(uint256(peth.balanceOf(this)));
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(weth.balanceOf(cdpContainer),    0 ether);

        assertEq(peth.totalSupply(), 0);
    }
    function testCashSafeOverCollatWithFreePeth() public {
        var cdp = cageSetup();
        cdpContainer.buyPethWithWeth(20 ether);   // give us some more peth
        mark(1 ether);
        top.triggerGlobalSettlement();

        assertEq(dai.balanceOf(this),  5 ether);
        assertEq(peth.balanceOf(this), 20 ether);
        assertEq(weth.balanceOf(this), 70 ether);
        assertEq(weth.balanceOf(cdpContainer),  25 ether);
        assertEq(weth.balanceOf(liquidator),   5 ether);

        cdpContainer.marginCall(cdp);
        cdpContainer.withdrawPeth(cdp, cdpContainer.getPethCollateral(cdp));
        liquidator.vent();
        top.flow();
        assertEq(peth.balanceOf(this), 25 ether);
        liquidator.cash(dai.balanceOf(this));
        cdpContainer.sellPethForWeth(uint256(peth.balanceOf(this)));
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(dai.balanceOf(this),   0 ether);
        assertEq(weth.balanceOf(cdpContainer),    0 ether);

        liquidator.vent();
        assertEq(dai.totalSupply(), 0);
        assertEq(peth.totalSupply(), 0);
    }
    function testFailCashSafeOverCollatWithFreePethExitBeforeBail() public {
        // fails because sellPethForWeth is before bail
        var cdp = cageSetup();
        cdpContainer.buyPethWithWeth(20 ether);   // give us some more peth
        mark(1 ether);
        top.triggerGlobalSettlement();

        liquidator.cash(dai.balanceOf(this));
        cdpContainer.sellPethForWeth(uint256(peth.balanceOf(this)));
        assertEq(peth.balanceOf(this), 0 ether);
        uint256 wethByDAI = 5 ether; // Adding 5 weth from 5 dai
        uint256 wethByPETH = wdiv(wmul(20 ether, 30 ether - wethByDAI), 30 ether);
        assertEq(weth.balanceOf(this), 70 ether + wethByDAI + wethByPETH);

        assertEq(dai.balanceOf(this), 0);
        assertEq(dai.totalSupply(), 0);
        assertEq(sin.totalSupply(), 0);

        cdpContainer.marginCall(cdp);
        cdpContainer.withdrawPeth(cdp, cdpContainer.getPethCollateral(cdp));
        liquidator.vent();
        top.flow();
        assertEq(peth.balanceOf(this), 5 ether); // peth retrieved by bail(cdp)

        cdpContainer.sellPethForWeth(uint256(peth.balanceOf(this)));
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(dai.balanceOf(this),   0 ether);
        assertEq(weth.balanceOf(cdpContainer),    0 ether);
        assertEq(dai.totalSupply(), 0);
        assertEq(sin.totalSupply(), 0);

        assertEq(peth.totalSupply(), 0);
    }
    function testCashUnsafeOverCollat() public {
        var cdp = cageSetup();
        cdpContainer.buyPethWithWeth(20 ether);   // give us some more peth
        var price = wdiv(3 ether, 4 ether);
        mark(price);
        top.triggerGlobalSettlement();        // 150% collat

        assertEq(dai.balanceOf(this),  5 ether);
        assertEq(peth.balanceOf(this), 20 ether);
        assertEq(weth.balanceOf(this), 70 ether);

        liquidator.cash(dai.balanceOf(this));
        assertEq(dai.balanceOf(this),   0 ether);
        assertEq(peth.balanceOf(this),  20 ether);

        uint256 wethByDAI = wdiv(wmul(5 ether, 4 ether), 3 ether);
        uint256 wethByPETH = 0;

        assertEq(weth.balanceOf(this), 70 ether + wethByDAI + wethByPETH);
        assertEq(weth.balanceOf(cdpContainer),  30 ether - wethByDAI - wethByPETH);

        // how much weth should be returned?
        // there were 10 weths initially, of which 5 were 100% collat
        // at the triggerGlobalSettlement price, 5 * 4 / 3 are 100% collat,
        // leaving 10 - 5 * 4 / 3 as excess = 3.333
        // this should all be returned
        var pethCollateral = cdpContainer.getPethCollateral(cdp);
        var tab = cdpContainer.tab(cdp);
        var pethToRecover = sub(pethCollateral, wdiv(tab, price));
        cdpContainer.marginCall(cdp);
        cdpContainer.withdrawPeth(cdp, cdpContainer.getPethCollateral(cdp));

        assertEq(peth.balanceOf(this), 20 ether + pethToRecover);
        assertEq(peth.balanceOf(cdpContainer),  0 ether);

        liquidator.vent();
        top.flow();
        cdpContainer.sellPethForWeth(uint256(peth.balanceOf(this)));
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(weth.balanceOf(cdpContainer),    0 ether);

        liquidator.vent();
        assertEq(peth.totalSupply(), 0);
        assertEq(dai.totalSupply(), 0);
    }
    function testCashAtCollat() public {
        var cdp = cageSetup();
        var price = wdiv(1 ether, 2 ether);  // 100% collat
        mark(price);
        top.triggerGlobalSettlement();

        assertEq(dai.balanceOf(this),  5 ether);
        assertEq(peth.balanceOf(this),  0 ether);
        assertEq(weth.balanceOf(this), 90 ether);
        liquidator.cash(dai.balanceOf(this));
        assertEq(dai.balanceOf(this),   0 ether);
        assertEq(peth.balanceOf(this),   0 ether);

        var saved = rmul(5 ether, rdiv(ONE_18, price));

        assertEq(weth.balanceOf(this),  90 ether + saved);
        assertEq(weth.balanceOf(cdpContainer),   10 ether - saved);

        // how much weth should be returned?
        // none :D
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(weth.balanceOf(cdpContainer),    0 ether);
        cdpContainer.marginCall(cdp);
        cdpContainer.withdrawPeth(cdp, cdpContainer.getPethCollateral(cdp));
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(weth.balanceOf(cdpContainer),    0 ether);

        liquidator.vent();
        assertEq(peth.totalSupply(), 0);
        assertEq(dai.totalSupply(), 0);
    }
    function testCashAtCollatFreePeth() public {
        var cdp = cageSetup();
        cdpContainer.buyPethWithWeth(20 ether);   // give us some more peth
        var price = wdiv(1 ether, 2 ether);  // 100% collat
        mark(price);
        top.triggerGlobalSettlement();

        assertEq(dai.balanceOf(this),   5 ether);
        assertEq(peth.balanceOf(this),  20 ether);
        assertEq(weth.balanceOf(this),  70 ether);

        liquidator.cash(dai.balanceOf(this));
        assertEq(dai.balanceOf(this),   0 ether);

        cdpContainer.marginCall(cdp);
        cdpContainer.withdrawPeth(cdp, cdpContainer.getPethCollateral(cdp));
        liquidator.vent();
        top.flow();
        cdpContainer.sellPethForWeth(uint256(peth.balanceOf(this)));
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(weth.balanceOf(cdpContainer),    0 ether);

        assertEq(peth.totalSupply(), 0);
    }
    function testFailCashAtCollatFreePethExitBeforeBail() public {
        var cdp = cageSetup();
        cdpContainer.buyPethWithWeth(20 ether);   // give us some more peth
        var price = wdiv(1 ether, 2 ether);  // 100% collat
        mark(price);
        top.triggerGlobalSettlement();

        assertEq(dai.balanceOf(this),  5 ether);
        assertEq(peth.balanceOf(this), 20 ether);
        assertEq(weth.balanceOf(this), 70 ether);

        liquidator.cash(dai.balanceOf(this));
        assertEq(dai.balanceOf(this),   0 ether);
        cdpContainer.sellPethForWeth(uint256(peth.balanceOf(this)));
        assertEq(peth.balanceOf(this),   0 ether);


        var wethByDAI = wmul(5 ether, 2 ether);
        var wethByPETH = wdiv(wmul(20 ether, 30 ether - wethByDAI), 30 ether);

        assertEq(weth.balanceOf(this), 70 ether + wethByDAI + wethByPETH);
        assertEq(weth.balanceOf(cdpContainer),  30 ether - wethByDAI - wethByPETH);

        assertEq(dai.totalSupply(), 0);
        assertEq(sin.totalSupply(), 0);

        cdpContainer.marginCall(cdp);
        cdpContainer.withdrawPeth(cdp, cdpContainer.getPethCollateral(cdp));
        liquidator.vent();
        cdpContainer.sellPethForWeth(uint256(peth.balanceOf(this)));

        // Cdp did not have peth to free, then the ramaining weth in cdpContainer can not be shared as there is not more peth to sellPethForWeth
        assertEq(weth.balanceOf(this), 70 ether + wethByDAI + wethByPETH);
        assertEq(weth.balanceOf(cdpContainer),  30 ether - wethByDAI - wethByPETH);

        assertEq(peth.totalSupply(), 0);
    }
    function testCashUnderCollat() public {
        var cdp = cageSetup();
        var price = wdiv(1 ether, 4 ether);  // 50% collat
        mark(price);
        top.triggerGlobalSettlement();

        assertEq(dai.balanceOf(this),  5 ether);
        assertEq(peth.balanceOf(this),  0 ether);
        assertEq(weth.balanceOf(this), 90 ether);
        liquidator.cash(dai.balanceOf(this));
        assertEq(dai.balanceOf(this),   0 ether);
        assertEq(peth.balanceOf(this),   0 ether);

        // get back all 10 weths, which are now only worth 2.5 ref
        // so you've lost 50% on you dai
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(weth.balanceOf(cdpContainer),    0 ether);

        // how much weth should be returned?
        // none :D
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(weth.balanceOf(cdpContainer),    0 ether);
        cdpContainer.marginCall(cdp);
        cdpContainer.withdrawPeth(cdp, cdpContainer.getPethCollateral(cdp));
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(weth.balanceOf(cdpContainer),    0 ether);

        liquidator.vent();
        assertEq(peth.totalSupply(), 0);
        assertEq(dai.totalSupply(), 0);
    }
    function testCashUnderCollatFreePeth() public {
        var cdp = cageSetup();
        cdpContainer.buyPethWithWeth(20 ether);   // give us some more peth
        var price = wdiv(1 ether, 4 ether);   // 50% collat
        mark(price);
        top.triggerGlobalSettlement();

        assertEq(dai.balanceOf(this),  5 ether);
        assertEq(weth.balanceOf(this), 70 ether);
        liquidator.cash(dai.balanceOf(this));
        assertEq(dai.balanceOf(this),  0 ether);
        // returns 20 weths, taken from the free peth,
        // dai is made whole
        assertEq(weth.balanceOf(this), 90 ether);

        assertEq(peth.balanceOf(this),  20 ether);
        cdpContainer.marginCall(cdp);
        cdpContainer.withdrawPeth(cdp, cdpContainer.getPethCollateral(cdp));

        liquidator.vent();
        top.flow();
        cdpContainer.sellPethForWeth(uint256(peth.balanceOf(this)));
        assertEq(peth.balanceOf(this),   0 ether);
        // the peth has taken a 50% loss - 10 weths returned from 20 put in
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(weth.balanceOf(cdpContainer),    0 ether);

        assertEq(dai.totalSupply(), 0);
        assertEq(peth.totalSupply(), 0);
    }
    function testCashSafeOverCollatAndMock() public {
        testCashSafeOverCollat();
        weth.approve(liquidator, uint(-1));
        liquidator.mock(5 ether);
        assertEq(dai.balanceOf(this), 5 ether);
        assertEq(weth.balanceOf(this), 95 ether);
        assertEq(weth.balanceOf(liquidator), 5 ether);
    }
    function testCashSafeOverCollatWithFreePethAndMock() public {
        testCashSafeOverCollatWithFreePeth();
        weth.approve(liquidator, uint(-1));
        liquidator.mock(5 ether);
        assertEq(dai.balanceOf(this), 5 ether);
        assertEq(weth.balanceOf(this), 95 ether);
        assertEq(weth.balanceOf(liquidator), 5 ether);
    }
    function testFailCashSafeOverCollatWithFreePethExitBeforeBailAndMock() public {
        testFailCashSafeOverCollatWithFreePethExitBeforeBail();
        weth.approve(liquidator, uint(-1));
        liquidator.mock(5 ether);
        assertEq(dai.balanceOf(this), 5 ether);
        assertEq(weth.balanceOf(this), 95 ether);
        assertEq(weth.balanceOf(liquidator), 5 ether);
    }

    function testThreeCdpsOverCollat() public {
        var cdp = cageSetup();
        cdpContainer.buyPethWithWeth(90 ether);   // give us some more peth
        var cdp2 = cdpContainer.open(); // open a new cdp
        cdpContainer.depositPeth(cdp2, 20 ether); // lock collateral but not draw DAI
        var cdp3 = cdpContainer.open(); // open a new cdp
        cdpContainer.depositPeth(cdp3, 20 ether); // lock collateral but not draw DAI

        assertEq(weth.balanceOf(liquidator), 0);
        assertEq(weth.balanceOf(cdpContainer), 100 ether);
        assertEq(weth.balanceOf(this), 0);
        assertEq(peth.balanceOf(this), 50 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 50 ether); // locked peth

        uint256 price = 1 ether;
        mark(price);
        top.triggerGlobalSettlement();

        assertEq(weth.balanceOf(liquidator), 5 ether); // Needed to payout 5 dai
        assertEq(weth.balanceOf(cdpContainer), 95 ether);

        cdpContainer.marginCall(cdp);
        cdpContainer.withdrawPeth(cdp, cdpContainer.getPethCollateral(cdp)); // 5 peth recovered, and 5 peth burnt

        assertEq(peth.balanceOf(this), 55 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 40 ether); // locked peth

        cdpContainer.marginCall(cdp2);
        cdpContainer.withdrawPeth(cdp2, cdpContainer.getPethCollateral(cdp2)); // 20 peth recovered

        assertEq(peth.balanceOf(this), 75 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 20 ether); // locked peth

        cdpContainer.marginCall(cdp3);
        cdpContainer.withdrawPeth(cdp3, cdpContainer.getPethCollateral(cdp3)); // 20 peth recovered

        assertEq(peth.balanceOf(this), 95 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 0); // locked peth

        liquidator.cash(dai.balanceOf(this));

        assertEq(dai.balanceOf(this), 0);
        assertEq(weth.balanceOf(this), 5 ether);

        liquidator.vent();
        top.flow();
        cdpContainer.sellPethForWeth(uint256(peth.balanceOf(this))); // sellPethForWeth 95 peth at price 95/95

        assertEq(weth.balanceOf(cdpContainer), 0);
        assertEq(weth.balanceOf(liquidator), 0);
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(peth.totalSupply(), 0);
    }
    function testThreeCdpsAtCollat() public {
        var cdp = cageSetup();
        cdpContainer.buyPethWithWeth(90 ether);   // give us some more peth
        var cdp2 = cdpContainer.open(); // open a new cdp
        cdpContainer.depositPeth(cdp2, 20 ether); // lock collateral but not draw DAI
        var cdp3 = cdpContainer.open(); // open a new cdp
        cdpContainer.depositPeth(cdp3, 20 ether); // lock collateral but not draw DAI

        assertEq(weth.balanceOf(liquidator), 0);
        assertEq(weth.balanceOf(cdpContainer), 100 ether);
        assertEq(weth.balanceOf(this), 0);
        assertEq(peth.balanceOf(this), 50 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 50 ether); // locked peth

        var price = wdiv(1 ether, 2 ether);
        mark(price);
        top.triggerGlobalSettlement();

        assertEq(weth.balanceOf(liquidator), 10 ether); // Needed to payout 10 dai
        assertEq(weth.balanceOf(cdpContainer), 90 ether);

        cdpContainer.marginCall(cdp);
        cdpContainer.withdrawPeth(cdp, cdpContainer.getPethCollateral(cdp)); // 10 peth burnt

        assertEq(peth.balanceOf(this), 50 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 40 ether); // locked peth

        cdpContainer.marginCall(cdp2);
        cdpContainer.withdrawPeth(cdp2, cdpContainer.getPethCollateral(cdp2)); // 20 peth recovered

        assertEq(peth.balanceOf(this), 70 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 20 ether); // locked peth

        cdpContainer.marginCall(cdp3);
        cdpContainer.withdrawPeth(cdp3, cdpContainer.getPethCollateral(cdp3)); // 20 peth recovered

        assertEq(peth.balanceOf(this), 90 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 0); // locked peth

        liquidator.cash(dai.balanceOf(this));

        assertEq(dai.balanceOf(this), 0);
        assertEq(weth.balanceOf(this), 10 ether);

        liquidator.vent();
        top.flow();
        cdpContainer.sellPethForWeth(uint256(peth.balanceOf(this))); // sellPethForWeth 90 peth at price 90/90

        assertEq(weth.balanceOf(cdpContainer), 0);
        assertEq(weth.balanceOf(liquidator), 0);
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(peth.totalSupply(), 0);
    }
    function testThreeCdpsUnderCollat() public {
        var cdp = cageSetup();
        cdpContainer.buyPethWithWeth(90 ether);   // give us some more peth
        var cdp2 = cdpContainer.open(); // open a new cdp
        cdpContainer.depositPeth(cdp2, 20 ether); // lock collateral but not draw DAI
        var cdp3 = cdpContainer.open(); // open a new cdp
        cdpContainer.depositPeth(cdp3, 20 ether); // lock collateral but not draw DAI

        assertEq(weth.balanceOf(liquidator), 0);
        assertEq(weth.balanceOf(cdpContainer), 100 ether);
        assertEq(weth.balanceOf(this), 0);
        assertEq(peth.balanceOf(this), 50 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 50 ether); // locked peth

        var price = wdiv(1 ether, 4 ether);
        mark(price);
        top.triggerGlobalSettlement();

        assertEq(weth.balanceOf(liquidator), 20 ether); // Needed to payout 5 dai
        assertEq(weth.balanceOf(cdpContainer), 80 ether);

        cdpContainer.marginCall(cdp);
        cdpContainer.withdrawPeth(cdp, cdpContainer.getPethCollateral(cdp)); // No peth is retrieved as the cdp doesn't even cover the debt. 10 locked peth in cdp are burnt from cdpContainer

        assertEq(peth.balanceOf(this), 50 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 40 ether); // locked peth

        cdpContainer.marginCall(cdp2);
        cdpContainer.withdrawPeth(cdp2, cdpContainer.getPethCollateral(cdp2)); // 20 peth recovered

        assertEq(peth.balanceOf(this), 70 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 20 ether); // locked peth

        cdpContainer.marginCall(cdp3);
        cdpContainer.withdrawPeth(cdp3, cdpContainer.getPethCollateral(cdp3)); // 20 peth recovered

        assertEq(peth.balanceOf(this), 90 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 0); // locked peth

        liquidator.cash(dai.balanceOf(this));

        assertEq(dai.balanceOf(this), 0);
        assertEq(weth.balanceOf(this), 20 ether);

        liquidator.vent();
        top.flow();
        cdpContainer.sellPethForWeth(uint256(peth.balanceOf(this))); // sellPethForWeth 90 peth at price 80/90

        assertEq(weth.balanceOf(cdpContainer), 0);
        assertEq(weth.balanceOf(liquidator), 0);
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(peth.totalSupply(), 0);
    }
    function testThreeCdpsPETHZeroValue() public {
        var cdp = cageSetup();
        cdpContainer.buyPethWithWeth(90 ether);   // give us some more peth
        var cdp2 = cdpContainer.open(); // open a new cdp
        cdpContainer.depositPeth(cdp2, 20 ether); // lock collateral but not draw DAI
        var cdp3 = cdpContainer.open(); // open a new cdp
        cdpContainer.depositPeth(cdp3, 20 ether); // lock collateral but not draw DAI

        assertEq(weth.balanceOf(liquidator), 0);
        assertEq(weth.balanceOf(cdpContainer), 100 ether);
        assertEq(weth.balanceOf(this), 0);
        assertEq(peth.balanceOf(this), 50 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 50 ether); // locked peth

        var price = wdiv(1 ether, 20 ether);
        mark(price);
        top.triggerGlobalSettlement();

        assertEq(weth.balanceOf(liquidator), 100 ether); // Needed to payout 5 dai
        assertEq(weth.balanceOf(cdpContainer), 0 ether);

        cdpContainer.marginCall(cdp);
        cdpContainer.withdrawPeth(cdp, cdpContainer.getPethCollateral(cdp)); // No peth is retrieved as the cdp doesn't even cover the debt. 10 locked peth in cdp are burnt from cdpContainer

        assertEq(peth.balanceOf(this), 50 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 40 ether); // locked peth

        cdpContainer.marginCall(cdp2);
        cdpContainer.withdrawPeth(cdp2, cdpContainer.getPethCollateral(cdp2)); // 20 peth recovered

        assertEq(peth.balanceOf(this), 70 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 20 ether); // locked peth

        cdpContainer.marginCall(cdp3);
        cdpContainer.withdrawPeth(cdp3, cdpContainer.getPethCollateral(cdp3)); // 20 peth recovered

        assertEq(peth.balanceOf(this), 90 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 0); // locked peth

        liquidator.cash(dai.balanceOf(this));

        assertEq(dai.balanceOf(this), 0);
        assertEq(weth.balanceOf(this), 100 ether);

        liquidator.vent();
        top.flow();
        cdpContainer.sellPethForWeth(uint256(peth.balanceOf(this))); // sellPethForWeth 90 peth at price 0/90

        assertEq(weth.balanceOf(cdpContainer), 0);
        assertEq(weth.balanceOf(liquidator), 0);
        assertEq(weth.balanceOf(this), 100 ether);
        assertEq(peth.totalSupply(), 0);
    }

    function testPeriodicFixValue() public {
        cageSetup();

        assertEq(weth.balanceOf(liquidator), 0);
        assertEq(weth.balanceOf(cdpContainer), 10 ether);
        assertEq(weth.balanceOf(this), 90 ether);
        assertEq(peth.balanceOf(this), 0 ether); // free peth
        assertEq(peth.balanceOf(cdpContainer), 10 ether); // locked peth

        FakePerson person = new FakePerson(liquidator);
        dai.transfer(person, 2.5 ether); // Transfer half of DAI balance to the other user

        var price = rdiv(9 ether, 8 ether);
        mark(price);
        top.triggerGlobalSettlement();

        assertEq(weth.balanceOf(liquidator), rmul(5 ether, top.wethPerDaiAtSettlement())); // Needed to payout 5 dai
        assertEq(weth.balanceOf(cdpContainer), sub(10 ether, rmul(5 ether, top.wethPerDaiAtSettlement())));

        liquidator.cash(dai.balanceOf(this));

        assertEq(dai.balanceOf(this),     0 ether);
        assertEq(dai.balanceOf(person), 2.5 ether);
        assertEq(weth.balanceOf(this), add(90 ether, rmul(2.5 ether, top.wethPerDaiAtSettlement())));

        person.cash();
    }

    function testCageExitAfterPeriod() public {
        var cdp = cageSetup();
        mom.setMat(ray(1 ether));  // 100% collat limit
        cdpContainer.withdrawPeth(cdp, 5 ether);  // 100% collat

        assertEq(uint(top.caged()), 0);
        top.triggerGlobalSettlement();
        assertEq(uint(top.caged()), vox.getCurrentTimestamp());

        // sellPethForWeth fails because ice != 0 && fog !=0 and not enough time passed
        assertTrue(!cdpContainer.call(bytes4(keccak256('sellPethForWeth(uint256)')), 5 ether));

        top.setCooldown(1 days);
        warp(1 days);
        assertTrue(!cdpContainer.call(bytes4(keccak256('sellPethForWeth(uint256)')), 5 ether));

        warp(1 seconds);
        top.flow();
        assertEq(peth.balanceOf(this), 5 ether);
        assertEq(weth.balanceOf(this), 90 ether);
        assertTrue(cdpContainer.call(bytes4(keccak256('sellPethForWeth(uint256)')), 4 ether));
        assertEq(peth.balanceOf(this), 1 ether);
        // n.b. we don't get back 4 as there is still peth in the cdp
        assertEq(weth.balanceOf(this), 92 ether);

        // now we can cash in our dai
        assertEq(dai.balanceOf(this), 5 ether);
        liquidator.cash(dai.balanceOf(this));
        assertEq(dai.balanceOf(this), 0 ether);
        assertEq(weth.balanceOf(this), 97 ether);

        // the remaining weth can be claimed only if the cdp peth is burned
        assertEq(cdpContainer.totalCollateralizedPeth(), 5 ether);
        assertEq(liquidator.fog(), 0 ether);
        assertEq(cdpContainer.din(), 5 ether);
        assertEq(liquidator.woe(), 0 ether);
        cdpContainer.marginCall(cdp);
        assertEq(cdpContainer.totalCollateralizedPeth(), 0 ether);
        assertEq(liquidator.fog(), 5 ether);
        assertEq(cdpContainer.din(), 0 ether);
        assertEq(liquidator.woe(), 5 ether);

        liquidator.vent();
        assertEq(liquidator.fog(), 0 ether);

        // now this remaining 1 peth will claim all the remaining 3 ether.
        // this is why exiting early is bad if you want to maximise returns.
        // if we had exited with all the peth earlier, there would be 2.5 weth
        // trapped in the cdpContainer.
        cdpContainer.sellPethForWeth(1 ether);
        assertEq(peth.balanceOf(this),   0 ether);
        assertEq(weth.balanceOf(this), 100 ether);
    }

    function testShutEmptyCdp() public {
        var cdp = cdpContainer.open();
        var (owner,,,) = cdpContainer.cdps(cdp);
        assertEq(owner, this);
        cdpContainer.shut(cdp);
        (owner,,,) = cdpContainer.cdps(cdp);
        assertEq(owner, 0);
    }
}

contract LiquidationTest is DaiTestBase {
    function liq(bytes32 cdp) internal returns (uint256) {
        // compute the liquidation price of a cdp
        var jam = rmul(cdpContainer.getPethCollateral(cdp), cdpContainer.wethPerPeth());  // this many eth
        var con = rmul(cdpContainer.tab(cdp), vox.par());  // this much ref debt
        var min = rmul(con, cdpContainer.liquidationRatio27());        // minimum ref debt
        return wdiv(min, jam);
    }
    function testLiq() public {
        mom.setCap(100 ether);
        mark(2 ether);

        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);
        cdpContainer.withdrawDai(cdp, 10 ether);        // 200% collateralisation

        mom.setMat(ray(1 ether));         // require 100% collateralisation
        assertEq(liq(cdp), 1 ether);

        mom.setMat(ray(3 ether / 2));     // require 150% collateralisation
        assertEq(liq(cdp), wdiv(3 ether, 2 ether));

        mark(6 ether);
        assertEq(liq(cdp), wdiv(3 ether, 2 ether));

        cdpContainer.withdrawDai(cdp, 30 ether);
        assertEq(liq(cdp), 6 ether);

        cdpContainer.buyPethWithWeth(10 ether);
        assertEq(liq(cdp), 6 ether);

        cdpContainer.depositPeth(cdp, 10 ether);  // now 40 drawn on 20 weth == 120 ref
        assertEq(liq(cdp), 3 ether);
    }
    function collat(bytes32 cdp) internal returns (uint256) {
        // compute the collateralised fraction of a cdp
        var pro = rmul(cdpContainer.getPethCollateral(cdp), cdpContainer.usdPerPeth());
        var con = rmul(cdpContainer.tab(cdp), vox.par());
        return wdiv(pro, con);
    }
    function testCollat() public {
        mom.setCap(100 ether);
        mark(2 ether);

        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);
        cdpContainer.withdrawDai(cdp, 10 ether);

        assertEq(collat(cdp), 2 ether);  // 200%

        mark(4 ether);
        assertEq(collat(cdp), 4 ether);  // 400%

        cdpContainer.withdrawDai(cdp, 15 ether);
        assertEq(collat(cdp), wdiv(8 ether, 5 ether));  // 160%

        mark(5 ether);
        cdpContainer.withdrawPeth(cdp, 5 ether);
        assertEq(collat(cdp), 1 ether);  // 100%

        mark(4 ether);
        assertEq(collat(cdp), wdiv(4 ether, 5 ether));  // 80%

        cdpContainer.depositDai(cdp, 9 ether);
        assertEq(collat(cdp), wdiv(5 ether, 4 ether));  // 125%
    }

    function testBustMint() public {
        mom.setCap(100 ether);
        mom.setMat(ray(wdiv(3 ether, 2 ether)));  // 150% liq limit
        mark(2 ether);

        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);

        mark(3 ether);
        cdpContainer.withdrawDai(cdp, 16 ether);  // 125% collat
        mark(2 ether);

        assertTrue(!cdpContainer.isAboveMarginCallThreshold(cdp));
        cdpContainer.marginCall(cdp);
        // 20 ref of weth on 16 ref of dai
        // 125%
        // 100% = 16ref of weth == 8 weth
        assertEq(liquidator.fog(), 8 ether);

        // 8 peth for sale
        assertEq(cdpContainer.wethPerPeth(), ray(1 ether));

        // get 2 peth, pay 4 dai (25% of the debt)
        var dai_before = dai.balanceOf(this);
        var peth_before = peth.balanceOf(this);
        assertEq(dai_before, 16 ether);
        liquidator.bust(2 ether);
        var dai_after = dai.balanceOf(this);
        var peth_after = peth.balanceOf(this);
        assertEq(dai_before - dai_after, 4 ether);
        assertEq(peth_after - peth_before, 2 ether);

        // price drop. now remaining 6 peth cannot cover bad debt (12 dai)
        mark(1 ether);

        // get 6 peth, pay 6 dai
        liquidator.bust(6 ether);
        // no more peth remaining to sell
        assertEq(liquidator.fog(), 0);
        // but peth supply unchanged
        assertEq(peth.totalSupply(), 10 ether);

        // now peth will be minted
        liquidator.bust(2 ether);
        assertEq(peth.totalSupply(), 12 ether);
    }
    function testBustNoMint() public {
        mom.setCap(1000 ether);
        mom.setMat(ray(2 ether));    // 200% liq limit
        mom.setAxe(ray(1.5 ether));  // 150% liq penalty
        mark(20 ether);

        cdpContainer.buyPethWithWeth(10 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 10 ether);
        cdpContainer.withdrawDai(cdp, 100 ether);  // 200 % collat

        mark(15 ether);
        cdpContainer.marginCall(cdp);

        // nothing remains in the cdp
        assertEq(cdpContainer.tab(cdp), 0);
        assertEq(cdpContainer.getPethCollateral(cdp), 0);

        // all collateral is now fog
        assertEq(liquidator.fog(), 10 ether);
        assertEq(liquidator.woe(), 100 ether);

        // the fog is worth 150 dai and the woe is worth 100 dai.
        // If all the fog is sold, there will be a dai surplus.

        // get some more dai to buy with
        cdpContainer.buyPethWithWeth(10 ether);
        var mug = cdpContainer.open();
        cdpContainer.depositPeth(mug, 10 ether);
        cdpContainer.withdrawDai(mug, 50 ether);

        liquidator.bust(10 ether);
        assertEq(dai.balanceOf(this), 0 ether);
        assertEq(peth.balanceOf(this), 10 ether);
        assertEq(liquidator.fog(), 0 ether);
        assertEq(liquidator.woe(), 0 ether);
        assertEq(liquidator.joy(), 50 ether);

        // joy is available through boom
        assertEq(liquidator.bid(1 ether), 15 ether);
        liquidator.boom(2 ether);
        assertEq(dai.balanceOf(this), 30 ether);
        assertEq(peth.balanceOf(this),  8 ether);
        assertEq(liquidator.fog(), 0 ether);
        assertEq(liquidator.woe(), 0 ether);
        assertEq(liquidator.joy(), 20 ether);
    }
}

contract TapTest is DaiTestBase {
    function testTapSetup() public {
        assertEq(dai.balanceOf(liquidator), liquidator.joy());
        assertEq(sin.balanceOf(liquidator), liquidator.woe());
        assertEq(peth.balanceOf(liquidator), liquidator.fog());

        assertEq(liquidator.joy(), 0);
        assertEq(liquidator.woe(), 0);
        assertEq(liquidator.fog(), 0);

        dai.mint(liquidator, 3);
        sin.mint(liquidator, 4);
        peth.mint(liquidator, 5);

        assertEq(liquidator.joy(), 3);
        assertEq(liquidator.woe(), 4);
        assertEq(liquidator.fog(), 5);
    }
    // boom (flap) is surplus sale (dai for peth->burn)
    function testTapBoom() public {
        dai.mint(liquidator, 50 ether);
        cdpContainer.buyPethWithWeth(60 ether);

        assertEq(dai.balanceOf(this),  0 ether);
        assertEq(peth.balanceOf(this), 60 ether);
        liquidator.boom(50 ether);
        assertEq(dai.balanceOf(this), 50 ether);
        assertEq(peth.balanceOf(this), 10 ether);
        assertEq(liquidator.joy(), 0);
    }
    function testFailTapBoomOverJoy() public {
        dai.mint(liquidator, 50 ether);
        cdpContainer.buyPethWithWeth(60 ether);
        liquidator.boom(51 ether);
    }
    function testTapBoomHeals() public {
        dai.mint(liquidator, 60 ether);
        sin.mint(liquidator, 50 ether);
        cdpContainer.buyPethWithWeth(10 ether);

        liquidator.boom(0 ether);
        assertEq(liquidator.joy(), 10 ether);
    }
    function testFailTapBoomNetWoe() public {
        dai.mint(liquidator, 50 ether);
        sin.mint(liquidator, 60 ether);
        cdpContainer.buyPethWithWeth(10 ether);
        liquidator.boom(1 ether);
    }
    function testTapBoomBurnsPeth() public {
        dai.mint(liquidator, 50 ether);
        cdpContainer.buyPethWithWeth(60 ether);

        assertEq(peth.totalSupply(), 60 ether);
        liquidator.boom(20 ether);
        assertEq(peth.totalSupply(), 40 ether);
    }
    function testTapBoomIncreasesPer() public {
        dai.mint(liquidator, 50 ether);
        cdpContainer.buyPethWithWeth(60 ether);

        assertEq(cdpContainer.wethPerPeth(), ray(1 ether));
        liquidator.boom(30 ether);
        assertEq(cdpContainer.wethPerPeth(), ray(2 ether));
    }
    function testTapBoomMarkDep() public {
        dai.mint(liquidator, 50 ether);
        cdpContainer.buyPethWithWeth(50 ether);

        mark(2 ether);
        liquidator.boom(10 ether);
        assertEq(dai.balanceOf(this), 20 ether);
        assertEq(dai.balanceOf(liquidator),  30 ether);
        assertEq(peth.balanceOf(this), 40 ether);
    }
    function testTapBoomPerDep() public {
        dai.mint(liquidator, 50 ether);
        cdpContainer.buyPethWithWeth(50 ether);

        assertEq(cdpContainer.wethPerPeth(), ray(1 ether));
        peth.mint(50 ether);  // halves per
        assertEq(cdpContainer.wethPerPeth(), ray(.5 ether));

        liquidator.boom(10 ether);
        assertEq(dai.balanceOf(this),  5 ether);
        assertEq(dai.balanceOf(liquidator),  45 ether);
        assertEq(peth.balanceOf(this), 90 ether);
    }
    // flip is collateral sale (peth for dai)
    function testTapBustFlip() public {
        dai.mint(50 ether);
        cdpContainer.buyPethWithWeth(50 ether);
        peth.push(liquidator, 50 ether);
        assertEq(liquidator.fog(), 50 ether);

        assertEq(peth.balanceOf(this),  0 ether);
        assertEq(dai.balanceOf(this), 50 ether);
        liquidator.bust(30 ether);
        assertEq(peth.balanceOf(this), 30 ether);
        assertEq(dai.balanceOf(this), 20 ether);
    }
    function testFailTapBustFlipOverFog() public { // FAIL
        dai.mint(50 ether);
        cdpContainer.buyPethWithWeth(50 ether);
        peth.push(liquidator, 50 ether);

        liquidator.bust(51 ether);
    }
    function testTapBustFlipHealsNetJoy() public {
        dai.mint(liquidator, 10 ether);
        sin.mint(liquidator, 20 ether);
        cdpContainer.buyPethWithWeth(50 ether);
        peth.push(liquidator, 50 ether);

        dai.mint(15 ether);
        liquidator.bust(15 ether);
        assertEq(liquidator.joy(), 5 ether);
        assertEq(liquidator.woe(), 0 ether);
    }
    function testTapBustFlipHealsNetWoe() public {
        dai.mint(liquidator, 10 ether);
        sin.mint(liquidator, 20 ether);
        cdpContainer.buyPethWithWeth(50 ether);
        peth.push(liquidator, 50 ether);

        dai.mint(5 ether);
        liquidator.bust(5 ether);
        assertEq(liquidator.joy(), 0 ether);
        assertEq(liquidator.woe(), 5 ether);
    }
    // flop is debt sale (woe->peth for dai)
    function testTapBustFlop() public {
        cdpContainer.buyPethWithWeth(50 ether);  // avoid per=1 init case
        dai.mint(100 ether);
        sin.mint(liquidator, 50 ether);
        assertEq(liquidator.woe(), 50 ether);

        assertEq(peth.balanceOf(this),  50 ether);
        assertEq(dai.balanceOf(this), 100 ether);
        liquidator.bust(50 ether);
        assertEq(peth.balanceOf(this), 100 ether);
        assertEq(dai.balanceOf(this),  75 ether);
    }
    function testFailTapBustFlopNetJoy() public {
        cdpContainer.buyPethWithWeth(50 ether);  // avoid per=1 init case
        dai.mint(100 ether);
        sin.mint(liquidator, 50 ether);
        dai.mint(liquidator, 100 ether);

        liquidator.bust(1);  // anything but zero should fail
    }
    function testTapBustFlopMintsPeth() public {
        cdpContainer.buyPethWithWeth(50 ether);  // avoid per=1 init case
        dai.mint(100 ether);
        sin.mint(liquidator, 50 ether);

        assertEq(peth.totalSupply(),  50 ether);
        liquidator.bust(20 ether);
        assertEq(peth.totalSupply(),  70 ether);
    }
    function testTapBustFlopDecreasesPer() public {
        cdpContainer.buyPethWithWeth(50 ether);  // avoid per=1 init case
        dai.mint(100 ether);
        sin.mint(liquidator, 50 ether);

        assertEq(cdpContainer.wethPerPeth(), ray(1 ether));
        liquidator.bust(50 ether);
        assertEq(cdpContainer.wethPerPeth(), ray(.5 ether));
    }

    function testTapBustAsk() public {
        cdpContainer.buyPethWithWeth(50 ether);
        assertEq(liquidator.ask(50 ether), 50 ether);

        peth.mint(50 ether);
        assertEq(liquidator.ask(50 ether), 25 ether);

        peth.mint(100 ether);
        assertEq(liquidator.ask(50 ether), 12.5 ether);

        peth.burn(175 ether);
        assertEq(liquidator.ask(50 ether), 100 ether);

        peth.mint(25 ether);
        assertEq(liquidator.ask(50 ether), 50 ether);

        peth.mint(10 ether);
        // per = 5 / 6
        assertEq(liquidator.ask(60 ether), 50 ether);

        peth.mint(30 ether);
        // per = 5 / 9
        assertEq(liquidator.ask(90 ether), 50 ether);

        peth.mint(10 ether);
        // per = 1 / 2
        assertEq(liquidator.ask(100 ether), 50 ether);
    }
    // flipflop is debt sale when collateral present
    function testTapBustFlipFlopRounding() public {
        cdpContainer.buyPethWithWeth(50 ether);  // avoid per=1 init case
        dai.mint(100 ether);
        sin.mint(liquidator, 100 ether);
        peth.push(liquidator,  50 ether);
        assertEq(liquidator.joy(),   0 ether);
        assertEq(liquidator.woe(), 100 ether);
        assertEq(liquidator.fog(),  50 ether);

        assertEq(peth.balanceOf(this),   0 ether);
        assertEq(dai.balanceOf(this), 100 ether);
        assertEq(peth.totalSupply(),    50 ether);

        assertEq(cdpContainer.wethPerPeth(), ray(1 ether));
        assertEq(liquidator.s2s(), ray(1 ether));
        assertEq(cdpContainer.usdPerPeth(), ray(1 ether));
        assertEq(liquidator.ask(60 ether), 60 ether);
        liquidator.bust(60 ether);
        assertEq(cdpContainer.wethPerPeth(), rdiv(5, 6));
        assertEq(liquidator.s2s(), rdiv(5, 6));
        assertEq(cdpContainer.usdPerPeth(), rdiv(5, 6));
        // non ray prices would give small rounding error because wad math
        assertEq(liquidator.ask(60 ether), 50 ether);
        assertEq(peth.totalSupply(),    60 ether);
        assertEq(liquidator.fog(),             0 ether);
        assertEq(peth.balanceOf(this),  60 ether);
        assertEq(dai.balanceOf(this),  50 ether);
    }
    function testTapBustFlipFlop() public {
        cdpContainer.buyPethWithWeth(50 ether);  // avoid per=1 init case
        dai.mint(100 ether);
        sin.mint(liquidator, 100 ether);
        peth.push(liquidator,  50 ether);
        assertEq(liquidator.joy(),   0 ether);
        assertEq(liquidator.woe(), 100 ether);
        assertEq(liquidator.fog(),  50 ether);

        assertEq(peth.balanceOf(this),   0 ether);
        assertEq(dai.balanceOf(this), 100 ether);
        assertEq(peth.totalSupply(),    50 ether);
        assertEq(cdpContainer.wethPerPeth(), ray(1 ether));
        liquidator.bust(80 ether);
        assertEq(cdpContainer.wethPerPeth(), rdiv(5, 8));
        assertEq(peth.totalSupply(),    80 ether);
        assertEq(liquidator.fog(),             0 ether);
        assertEq(peth.balanceOf(this),  80 ether);
        assertEq(dai.balanceOf(this),  50 ether);  // expected 50, actual 50 ether + 2???!!!
    }
}

contract StabilityFeeTest is DaiTestBase {
    function testEraInit() public {
        assertEq(uint(vox.getCurrentTimestamp()), now);
    }
    function testEraWarp() public {
        warp(20);
        assertEq(uint(vox.getCurrentTimestamp()), now + 20);
    }
    function stabilityFeeSetup() public returns (bytes32 cdp) {
        mark(10 ether);
        weth.deposit.value(1000 ether)();

        mom.setCap(1000 ether);
        mom.setStabilityFee(1000000564701133626865910626);  // 5% / day
        cdp = cdpContainer.open();
        cdpContainer.buyPethWithWeth(100 ether);
        cdpContainer.depositPeth(cdp, 100 ether);
        cdpContainer.withdrawDai(cdp, 100 ether);
    }
    function testStabilityFeegetCurrentTimestamp() public {
        var cdp = stabilityFeeSetup();
        assertEq(cdpContainer.tab(cdp), 100 ether);
        warp(1 days);
        assertEq(cdpContainer.tab(cdp), 105 ether);
        warp(1 days);
        assertEq(cdpContainer.tab(cdp), 110.25 ether);
    }
    // rum doesn't change on drip
    function testStabilityFeeRum() public {
        stabilityFeeSetup();
        assertEq(cdpContainer.rum(),    100 ether);
        warp(1 days);
        cdpContainer.drip();
        assertEq(cdpContainer.rum(),    100 ether);
    }
    // din increases on drip
    function testStabilityFeeDin() public {
        stabilityFeeSetup();
        assertEq(cdpContainer.din(),    100 ether);
        warp(1 days);
        cdpContainer.drip();
        assertEq(cdpContainer.din(),    105 ether);
    }
    // StabilityFee accumulates as dai surplus, and CDP debt
    function testStabilityFeeJoy() public {
        var cdp = stabilityFeeSetup();
        assertEq(cdpContainer.tab(cdp), 100 ether);
        assertEq(cdpContainer.din(),    100 ether);
        assertEq(liquidator.joy(),      0 ether);
        warp(1 days);
        assertEq(cdpContainer.tab(cdp), 105 ether);
        assertEq(cdpContainer.din(),    105 ether);
        assertEq(liquidator.joy(),      5 ether);
    }
    function testStabilityFeeJoy2() public {
        var cdp = stabilityFeeSetup();
        assertEq(cdpContainer.tab(cdp), 100 ether);
        assertEq(cdpContainer.din(),    100 ether);
        assertEq(liquidator.joy(),      0 ether);
        warp(1 days);
        cdpContainer.drip();
        assertEq(cdpContainer.tab(cdp), 105 ether);
        assertEq(cdpContainer.din(),    105 ether);
        assertEq(liquidator.joy(),      5 ether);
        // now ensure din != rum
        cdpContainer.depositDai(cdp, 5 ether);
        assertEq(cdpContainer.tab(cdp), 100 ether);
        assertEq(cdpContainer.din(),    100 ether);
        assertEq(liquidator.joy(),      5 ether);
        warp(1 days);
        cdpContainer.drip();
        assertEq(cdpContainer.tab(cdp), 105 ether);
        assertEq(cdpContainer.din(),    105 ether);
        assertEq(liquidator.joy(),     10 ether);
    }
    function testStabilityFeeJoy3() public {
        var cdp = stabilityFeeSetup();
        assertEq(cdpContainer.tab(cdp), 100 ether);
        assertEq(cdpContainer.din(),    100 ether);
        assertEq(liquidator.joy(),      0 ether);
        warp(1 days);
        cdpContainer.drip();
        assertEq(cdpContainer.tab(cdp), 105 ether);
        assertEq(cdpContainer.din(),    105 ether);
        assertEq(liquidator.joy(),      5 ether);
        // now ensure rum changes
        cdpContainer.depositDai(cdp, 5 ether);
        assertEq(cdpContainer.tab(cdp), 100 ether);
        assertEq(cdpContainer.din(),    100 ether);
        assertEq(liquidator.joy(),      5 ether);
        warp(1 days);
        cdpContainer.drip();
        assertEq(cdpContainer.tab(cdp), 105 ether);
        assertEq(cdpContainer.din(),    105 ether);
        assertEq(liquidator.joy(),     10 ether);
        // and ensure the last rum != din either
        cdpContainer.depositDai(cdp, 5 ether);
        assertEq(cdpContainer.tab(cdp), 100 ether);
        assertEq(cdpContainer.din(),    100 ether);
        assertEq(liquidator.joy(),     10 ether);
        warp(1 days);
        cdpContainer.drip();
        assertEq(cdpContainer.tab(cdp), 105 ether);
        assertEq(cdpContainer.din(),    105 ether);
        assertEq(liquidator.joy(),     15 ether);
    }
    function testStabilityFeeDraw() public {
        var cdp = stabilityFeeSetup();
        warp(1 days);
        assertEq(cdpContainer.tab(cdp), 105 ether);
        cdpContainer.withdrawDai(cdp, 100 ether);
        assertEq(cdpContainer.tab(cdp), 205 ether);
        warp(1 days);
        assertEq(cdpContainer.tab(cdp), 215.25 ether);
    }
    function testStabilityFeeWipe() public {
        var cdp = stabilityFeeSetup();
        warp(1 days);
        assertEq(cdpContainer.tab(cdp), 105 ether);
        cdpContainer.depositDai(cdp, 50 ether);
        assertEq(cdpContainer.tab(cdp), 55 ether);
        warp(1 days);
        assertEq(cdpContainer.tab(cdp), 57.75 ether);
    }
    // collected fees are available through boom
    function testStabilityFeeBoom() public {
        stabilityFeeSetup();
        warp(1 days);
        // should have 5 dai available == 0.5 peth
        cdpContainer.buyPethWithWeth(0.5 ether);  // get some unlocked peth

        assertEq(peth.totalSupply(),   100.5 ether);
        assertEq(dai.balanceOf(liquidator),    0 ether);
        assertEq(sin.balanceOf(liquidator),    0 ether);
        assertEq(dai.balanceOf(this), 100 ether);
        cdpContainer.drip();
        assertEq(dai.balanceOf(liquidator),    5 ether);
        liquidator.boom(0.5 ether);
        assertEq(peth.totalSupply(),   100 ether);
        assertEq(dai.balanceOf(liquidator),    0 ether);
        assertEq(sin.balanceOf(liquidator),    0 ether);
        assertEq(dai.balanceOf(this), 105 ether);
    }
    // StabilityFee can flip a cdp to unsafe
    function testStabilityFeeSafe() public {
        var cdp = stabilityFeeSetup();
        mark(1 ether);
        assertTrue(cdpContainer.isAboveMarginCallThreshold(cdp));
        warp(1 days);
        assertTrue(!cdpContainer.isAboveMarginCallThreshold(cdp));
    }
    function testStabilityFeeBite() public {
        var cdp = stabilityFeeSetup();
        mark(1 ether);
        warp(1 days);
        assertEq(cdpContainer.tab(cdp), 105 ether);
        cdpContainer.marginCall(cdp);
        assertEq(cdpContainer.tab(cdp),   0 ether);
        assertEq(liquidator.woe(),    105 ether);
    }
    function testStabilityFeeBiteRounding() public {
        var cdp = stabilityFeeSetup();
        mark(1 ether);
        mom.setMat(ray(1.5 ether));
        mom.setAxe(ray(1.4 ether));
        mom.setStabilityFee(ray(1.000000001547126 ether));
        // log_named_uint('tab', cdpContainer.tab(cdp));
        // log_named_uint('sin', cdpContainer.din());
        for (uint i=0; i<=50; i++) {
            warp(10);
            // log_named_uint('tab', cdpContainer.tab(cdp));
            // log_named_uint('sin', cdpContainer.din());
        }
        uint256 debtAfterWarp = rmul(100 ether, rpow(cdpContainer.stabilityFee27(), 510));
        assertEq(cdpContainer.tab(cdp), debtAfterWarp);
        cdpContainer.marginCall(cdp);
        assertEq(cdpContainer.tab(cdp), 0 ether);
        assertEq(liquidator.woe(), rmul(100 ether, rpow(cdpContainer.stabilityFee27(), 510)));
    }
    function testStabilityFeeBail() public {
        var cdp = stabilityFeeSetup();
        warp(1 days);
        cdpContainer.drip();
        mark(10 ether);
        top.triggerGlobalSettlement();

        warp(1 days);  // should have no effect
        cdpContainer.drip();

        assertEq(peth.balanceOf(this),  0 ether);
        assertEq(peth.balanceOf(cdpContainer), 100 ether);
        cdpContainer.marginCall(cdp);
        cdpContainer.withdrawPeth(cdp, cdpContainer.getPethCollateral(cdp));
        assertEq(peth.balanceOf(this), 89.5 ether);
        assertEq(peth.balanceOf(cdpContainer),     0 ether);

        assertEq(dai.balanceOf(this),  100 ether);
        assertEq(weth.balanceOf(this), 1000 ether);
        liquidator.cash(dai.balanceOf(this));
        assertEq(dai.balanceOf(this),    0 ether);
        assertEq(weth.balanceOf(this), 1010 ether);
    }
    function testStabilityFeeCage() public {
        // after triggerGlobalSettlement, un-distributed stabilityFee27 revenue remains as joy - dai
        // surplus in the liquidator. The remaining joy, plus all outstanding
        // dai, balances the sin debt in the cdpContainer, plus any debt (woe) in
        // the liquidator.

        // The effect of this is that joy remaining in liquidator is
        // effectively distributed to all peth holders.
        var cdp = stabilityFeeSetup();
        warp(1 days);
        mark(10 ether);

        assertEq(liquidator.joy(), 0 ether);
        top.triggerGlobalSettlement();                // should drip up to date
        assertEq(liquidator.joy(), 5 ether);
        warp(1 days);  cdpContainer.drip();  // should have no effect
        assertEq(liquidator.joy(), 5 ether);

        var owe = cdpContainer.tab(cdp);
        assertEq(owe, 105 ether);
        assertEq(cdpContainer.din(), owe);
        assertEq(liquidator.woe(), 0);
        cdpContainer.marginCall(cdp);
        assertEq(cdpContainer.din(), 0);
        assertEq(liquidator.woe(), owe);
        assertEq(liquidator.joy(), 5 ether);
    }
}

contract WayTest is DaiTestBase {
    function waySetup() public returns (bytes32 cdp) {
        mark(10 ether);
        weth.deposit.value(1000 ether)();

        mom.setCap(1000 ether);

        cdp = cdpContainer.open();
        cdpContainer.buyPethWithWeth(100 ether);
        cdpContainer.depositPeth(cdp, 100 ether);
        cdpContainer.withdrawDai(cdp, 100 ether);
    }
    // what does way actually do?
    // it changes the value of dai relative to ref
    // way > 1 -> par increasing, more ref per dai
    // way < 1 -> par decreasing, less ref per dai

    // this changes the safety level of cdps,
    // affecting `draw`, `wipe`, `free` and `bite`

    // if way < 1, par is decreasing and the con (in ref)
    // of a cdp is decreasing, so cdp holders need
    // less ref to wipe (but the same dai)
    // This makes cdps *more* collateralised with time.
    function testTau() public {
        assertEq(uint(vox.getCurrentTimestamp()), now);
        assertEq(uint(vox.tau()), now);
    }
    function testWayPar() public {
        mom.setWay(999999406327787478619865402);  // -5% / day

        assertEq(wad(vox.par()), 1.00 ether);
        warp(1 days);
        assertEq(wad(vox.par()), 0.95 ether);

        mom.setWay(1000000021979553151239153027);  // 200% / year
        warp(1 years);
        assertEq(wad(vox.par()), 1.90 ether);
    }
    function testWayDecreasingPrincipal() public {
        var cdp = waySetup();
        mark(0.98 ether);
        assertTrue(!cdpContainer.isAboveMarginCallThreshold(cdp));

        mom.setWay(999999406327787478619865402);  // -5% / day
        warp(1 days);
        assertTrue(cdpContainer.isAboveMarginCallThreshold(cdp));
    }
    // `triggerGlobalSettlement` is slightly affected: the triggerGlobalSettlement price is
    // now in *dai per weth*, where before ref per weth
    // was equivalent.
    // `bail` is unaffected, as all values are in dai.
    function testWayCage() public {
        waySetup();

        mom.setWay(1000000021979553151239153027);  // 200% / year
        warp(1 years);  // par now 2

        // we have 100 dai
        // weth is worth 10 ref
        // dai is worth 2 ref
        // we should get back 100 / (10 / 2) = 20 weth

        top.triggerGlobalSettlement();

        assertEq(weth.balanceOf(this), 1000 ether);
        assertEq(dai.balanceOf(this),  100 ether);
        assertEq(dai.balanceOf(liquidator),     0 ether);
        liquidator.cash(dai.balanceOf(this));
        assertEq(weth.balanceOf(this), 1020 ether);
        assertEq(dai.balanceOf(this),    0 ether);
        assertEq(dai.balanceOf(liquidator),     0 ether);
    }

    // `boom` and `bust` as par is now needed to determine
    // the peth / dai price.
    function testWayBust() public {
        var cdp = waySetup();
        mark(0.5 ether);
        cdpContainer.marginCall(cdp);

        assertEq(liquidator.joy(),   0 ether);
        assertEq(liquidator.woe(), 100 ether);
        assertEq(liquidator.fog(), 100 ether);
        assertEq(dai.balanceOf(this), 100 ether);

        liquidator.bust(50 ether);

        assertEq(liquidator.fog(),  50 ether);
        assertEq(liquidator.woe(),  75 ether);
        assertEq(dai.balanceOf(this), 75 ether);

        mom.setWay(999999978020447331861593082);  // -50% / year
        warp(1 years);
        assertEq(wad(vox.par()), 0.5 ether);
        // dai now worth half as much, so we cover twice as much debt
        // for the same peth
        liquidator.bust(50 ether);

        assertEq(liquidator.fog(),   0 ether);
        assertEq(liquidator.woe(),  25 ether);
        assertEq(dai.balanceOf(this), 25 ether);
    }
}

contract GapTest is DaiTestBase {
    // boom and bust have a spread parameter
    function setUp() public {
        super.setUp();

        weth.deposit.value(500 ether)();
        cdpContainer.buyPethWithWeth(500 ether);

        dai.mint(500 ether);
        sin.mint(500 ether);

        mark(2 ether);  // 2 ref per eth => 2 dai per peth
    }
    function testGapDaiTapBid() public {
        mark(1 ether);
        mom.setTapGap(1.01 ether);  // 1% spread
        assertEq(liquidator.bid(1 ether), 0.99 ether);
        mark(2 ether);
        assertEq(liquidator.bid(1 ether), 1.98 ether);
    }
    function testGapDaiTapAsk() public {
        mark(1 ether);
        mom.setTapGap(1.01 ether);  // 1% spread
        assertEq(liquidator.ask(1 ether), 1.01 ether);
        mark(2 ether);
        assertEq(liquidator.ask(1 ether), 2.02 ether);
    }
    function testGapBoom() public {
        dai.push(liquidator, 198 ether);
        assertEq(liquidator.joy(), 198 ether);

        mom.setTapGap(1.01 ether);  // 1% spread

        var dai_before = dai.balanceOf(this);
        var peth_before = peth.balanceOf(this);
        liquidator.boom(50 ether);
        var dai_after = dai.balanceOf(this);
        var peth_after = peth.balanceOf(this);
        assertEq(dai_after - dai_before, 99 ether);
        assertEq(peth_before - peth_after, 50 ether);
    }
    function testGapBust() public {
        peth.push(liquidator, 100 ether);
        sin.push(liquidator, 200 ether);
        assertEq(liquidator.fog(), 100 ether);
        assertEq(liquidator.woe(), 200 ether);

        mom.setTapGap(1.01 ether);

        var dai_before = dai.balanceOf(this);
        var peth_before = peth.balanceOf(this);
        liquidator.bust(50 ether);
        var dai_after = dai.balanceOf(this);
        var peth_after = peth.balanceOf(this);
        assertEq(peth_after - peth_before,  50 ether);
        assertEq(dai_before - dai_after, 101 ether);
    }
    function testGapLimits() public {
        uint256 legal   = 1.04 ether;
        uint256 illegal = 1.06 ether;

        var setGap = bytes4(keccak256("setTapGap(uint256)"));

        assertTrue(mom.call(setGap, legal));
        assertEq(liquidator.wethToPethSpread18(), legal);

        assertTrue(!mom.call(setGap, illegal));
        assertEq(liquidator.wethToPethSpread18(), legal);
    }

    // buyPethWithWeth and sellPethForWeth have a spread parameter
    function testGapJarBidAsk() public {
        assertEq(cdpContainer.wethPerPeth(), ray(1 ether));
        assertEq(cdpContainer.bid(1 ether), 1 ether);
        assertEq(cdpContainer.ask(1 ether), 1 ether);

        mom.setCdpContainerGap(1.01 ether);
        assertEq(cdpContainer.bid(1 ether), 0.99 ether);
        assertEq(cdpContainer.ask(1 ether), 1.01 ether);

        assertEq(peth.balanceOf(this), 500 ether);
        assertEq(peth.totalSupply(),   500 ether);
        peth.burn(250 ether);

        assertEq(cdpContainer.wethPerPeth(), ray(2 ether));
        assertEq(cdpContainer.bid(1 ether), 1.98 ether);
        assertEq(cdpContainer.ask(1 ether), 2.02 ether);
    }
    function testGapJoin() public {
        weth.deposit.value(100 ether)();

        mom.setCdpContainerGap(1.05 ether);
        var peth_before = peth.balanceOf(this);
        var weth_before = weth.balanceOf(this);
        cdpContainer.buyPethWithWeth(100 ether);
        var peth_after = peth.balanceOf(this);
        var weth_after = weth.balanceOf(this);

        assertEq(peth_after - peth_before, 100 ether);
        assertEq(weth_before - weth_after, 105 ether);
    }
    function testGapExit() public {
        weth.deposit.value(100 ether)();
        cdpContainer.buyPethWithWeth(100 ether);

        mom.setCdpContainerGap(1.05 ether);
        var peth_before = peth.balanceOf(this);
        var weth_before = weth.balanceOf(this);
        cdpContainer.sellPethForWeth(100 ether);
        var peth_after = peth.balanceOf(this);
        var weth_after = weth.balanceOf(this);

        assertEq(weth_after - weth_before,  95 ether);
        assertEq(peth_before - peth_after, 100 ether);
    }
}

contract GasTest is DaiTestBase {
    bytes32 cdp;
    function setUp() public {
        super.setUp();

        mark(1 ether);
        weth.deposit.value(1000 ether)();

        mom.setCap(1000 ether);
        mom.setAxe(ray(1 ether));
        mom.setMat(ray(1 ether));
        mom.setStabilityFee(ray(1 ether));
        mom.setFee(ray(1 ether));
        mom.setCdpContainerGap(1 ether);
        mom.setTapGap(1 ether);

        cdp = cdpContainer.open();
        cdpContainer.buyPethWithWeth(1000 ether);
        cdpContainer.depositPeth(cdp, 500 ether);
        cdpContainer.withdrawDai(cdp, 100 ether);
    }
    function doLock(uint256 wad) public logs_gas {
        cdpContainer.depositPeth(cdp, wad);
    }
    function doFree(uint256 wad) public logs_gas {
        cdpContainer.withdrawPeth(cdp, wad);
    }
    function doDraw(uint256 wad) public logs_gas {
        cdpContainer.withdrawDai(cdp, wad);
    }
    function doWipe(uint256 wad) public logs_gas {
        cdpContainer.depositDai(cdp, wad);
    }
    function doDrip() public logs_gas {
        cdpContainer.drip();
    }
    function doBoom(uint256 wad) public logs_gas {
        liquidator.boom(wad);
    }

    uint256 tic = 15 seconds;

    function testGasLock() public {
        warp(tic);
        doLock(100 ether);
        // assertTrue(false);
    }
    function testGasFree() public {
        warp(tic);
        doFree(100 ether);
        // assertTrue(false);
    }
    function testGasDraw() public {
        warp(tic);
        doDraw(100 ether);
        // assertTrue(false);
    }
    function testGasWipe() public {
        warp(tic);
        doWipe(100 ether);
        // assertTrue(false);
    }
    function testGasBoom() public {
        warp(tic);
        cdpContainer.buyPethWithWeth(10 ether);
        dai.mint(100 ether);
        dai.push(liquidator, 100 ether);
        peth.approve(liquidator, uint(-1));
        doBoom(1 ether);
        // assertTrue(false);
    }
    function testGasBoomHeal() public {
        warp(tic);
        cdpContainer.buyPethWithWeth(10 ether);
        dai.mint(100 ether);
        sin.mint(100 ether);
        dai.push(liquidator, 100 ether);
        sin.push(liquidator,  50 ether);
        peth.approve(liquidator, uint(-1));
        doBoom(1 ether);
        // assertTrue(false);
    }
    function testGasDripNoop() public {
        cdpContainer.drip();
        doDrip();
    }
    function testGasDrip1s() public {
        warp(1 seconds);
        doDrip();
    }
    function testGasDrip1m() public {
        warp(1 minutes);
        doDrip();
    }
    function testGasDrip1h() public {
        warp(1 hours);
        doDrip();
    }
    function testGasDrip1d() public {
        warp(1 days);
        doDrip();
    }
}

contract FeeTest is DaiTestBase {
    function governanceFeeSetup() public returns (bytes32 cdp) {
        mark(10 ether);
        mark(mkr, 1 ether / 2);
        weth.deposit.value(1000 ether)();
        mkr.mint(100 ether);

        mom.setCap(1000 ether);
        mom.setFee(1000000564701133626865910626);  // 5% / day

        // warp(1 days);  // make chi,rhi != 1

        cdp = cdpContainer.open();
        cdpContainer.buyPethWithWeth(100 ether);
        cdpContainer.depositPeth(cdp, 100 ether);
        cdpContainer.withdrawDai(cdp, 100 ether);
    }
    function testFeeSet() public {
        assertEq(cdpContainer.governanceFee27(), ray(1 ether));
        mom.setFee(ray(1.000000001 ether));
        assertEq(cdpContainer.governanceFee27(), ray(1.000000001 ether));
    }
    function testFeeSetup() public {
        governanceFeeSetup();
        assertEq(cdpContainer.chi(), ray(1 ether));
        assertEq(cdpContainer.rhi(), ray(1 ether));
    }
    function testFeeDrip() public {
        governanceFeeSetup();
        warp(1 days);
        assertEq(cdpContainer.chi() / 10 ** 9, 1.00 ether);
        assertEq(cdpContainer.rhi() / 10 ** 9, 1.05 ether);
    }
    // Unpaid fees do not accumulate as sin
    function testFeeIce() public {
        var cdp = governanceFeeSetup();
        assertEq(cdpContainer.din(),    100 ether);
        assertEq(cdpContainer.tab(cdp), 100 ether);
        assertEq(cdpContainer.rap(cdp),   0 ether);
        warp(1 days);
        assertEq(cdpContainer.din(),    100 ether);
        assertEq(cdpContainer.tab(cdp), 100 ether);
        assertEq(cdpContainer.rap(cdp),   5 ether);
    }
    function testFeeDraw() public {
        var cdp = governanceFeeSetup();
        warp(1 days);
        assertEq(cdpContainer.rap(cdp),   5 ether);
        cdpContainer.withdrawDai(cdp, 100 ether);
        assertEq(cdpContainer.rap(cdp),   5 ether);
        warp(1 days);
        assertEq(cdpContainer.rap(cdp),  15.25 ether);
    }
    function testFeeWipe() public {
        var cdp = governanceFeeSetup();
        warp(1 days);
        assertEq(cdpContainer.rap(cdp),   5 ether);
        cdpContainer.depositDai(cdp, 50 ether);
        assertEq(cdpContainer.rap(cdp),  2.5 ether);
        warp(1 days);
        assertEq(cdpContainer.rap(cdp),  5.125 ether);
    }
    function testFeeCalcFromRap() public {
        var cdp = governanceFeeSetup();

        assertEq(cdpContainer.tab(cdp), 100 ether);
        assertEq(cdpContainer.rap(cdp),   0 ether);
        warp(1 days);
        assertEq(cdpContainer.tab(cdp), 100 ether);
        assertEq(cdpContainer.rap(cdp),   5 ether);
    }
    function testFeeWipePays() public {
        var cdp = governanceFeeSetup();
        warp(1 days);

        assertEq(cdpContainer.rap(cdp),          5 ether);
        assertEq(mkr.balanceOf(this), 100 ether);
        cdpContainer.depositDai(cdp, 50 ether);
        assertEq(cdpContainer.tab(cdp),         50 ether);
        assertEq(mkr.balanceOf(this),  95 ether);
    }
    function testFeeWipeMoves() public {
        var cdp = governanceFeeSetup();
        warp(1 days);

        assertEq(mkr.balanceOf(this), 100 ether);
        assertEq(mkr.balanceOf(pit),    0 ether);
        cdpContainer.depositDai(cdp, 50 ether);
        assertEq(mkr.balanceOf(this),  95 ether);
        assertEq(mkr.balanceOf(pit),    5 ether);
    }
    function testFeeWipeAll() public {
        var cdp = governanceFeeSetup();
        warp(1 days);

        var wad = cdpContainer.tab(cdp);
        assertEq(wad, 100 ether);
        var owe = cdpContainer.rap(cdp);
        assertEq(owe, 5 ether);

        var ( , , outstandingDebtAndStabilityFees, ire) = cdpContainer.cdps(cdp);
        assertEq(outstandingDebtAndStabilityFees, 100 ether);
        assertEq(ire, 100 ether);
        assertEq(rdiv(wad, cdpContainer.chi()), outstandingDebtAndStabilityFees);
        assertEq(rdiv(add(wad, owe), cdpContainer.rhi()), ire);

        assertEq(cdpContainer.rap(cdp),   5 ether);
        assertEq(cdpContainer.tab(cdp), 100 ether);
        assertEq(mkr.balanceOf(this), 100 ether);
        cdpContainer.depositDai(cdp, 100 ether);
        assertEq(cdpContainer.rap(cdp), 0 ether);
        assertEq(cdpContainer.tab(cdp), 0 ether);
        assertEq(mkr.balanceOf(this), 90 ether);
    }
    function testFeeWipeNoFeed() public {
        var cdp = governanceFeeSetup();
        daiPerMaker.void();
        warp(1 days);

        // fees continue to accumulate
        assertEq(cdpContainer.rap(cdp),   5 ether);

        // mkr is no longer taken
        assertEq(mkr.balanceOf(this), 100 ether);
        cdpContainer.depositDai(cdp, 50 ether);
        assertEq(mkr.balanceOf(this), 100 ether);

        // fees are still wiped proportionally
        assertEq(cdpContainer.rap(cdp),  2.5 ether);
        warp(1 days);
        assertEq(cdpContainer.rap(cdp),  5.125 ether);
    }
    function testFeeWipeShut() public {
        var cdp = governanceFeeSetup();
        warp(1 days);
        cdpContainer.shut(cdp);
    }
    function testFeeWipeShutEmpty() public {
        governanceFeeSetup();
        var cdp = cdpContainer.open();
        cdpContainer.buyPethWithWeth(100 ether);
        cdpContainer.depositPeth(cdp, 100 ether);
        warp(1 days);
        cdpContainer.shut(cdp);
    }
}

contract PitTest is DaiTestBase {
    function testPitBurns() public {
        mkr.mint(1 ether);
        assertEq(mkr.balanceOf(pit), 0 ether);
        mkr.push(pit, 1 ether);

        // mock mkr authority
        var guard = new DSGuard();
        guard.permit(pit, mkr, bytes4(keccak256('burn(uint256)')));
        mkr.setAuthority(guard);

        assertEq(mkr.balanceOf(pit), 1 ether);
        pit.burn(mkr);
        assertEq(mkr.balanceOf(pit), 0 ether);
    }
}

contract FeeStabilityFeeTest is DaiTestBase {
    function governanceFeeSetup() public returns (bytes32 cdp) {
        mark(10 ether);
        mark(mkr, 1 ether / 2);
        weth.deposit.value(1000 ether)();
        mkr.mint(100 ether);

        mom.setCap(1000 ether);
        mom.setFee(1000000564701133626865910626);  // 5% / day
        mom.setStabilityFee(1000000564701133626865910626);  // 5% / day

        // warp(1 days);  // make chi,rhi != 1

        cdp = cdpContainer.open();
        cdpContainer.buyPethWithWeth(100 ether);
        cdpContainer.depositPeth(cdp, 100 ether);
        cdpContainer.withdrawDai(cdp, 100 ether);
    }
    function testFeeStabilityFeeDrip() public {
        governanceFeeSetup();
        warp(1 days);
        assertEq(cdpContainer.chi() / 10 ** 9, 1.0500 ether);
        assertEq(cdpContainer.rhi() / 10 ** 9, 1.1025 ether);
    }
    // Unpaid fees do not accumulate as sin
    function testFeeStabilityFeeIce() public {
        var cdp = governanceFeeSetup();

        assertEq(cdpContainer.tab(cdp), 100 ether);
        assertEq(cdpContainer.rap(cdp),   0 ether);

        assertEq(cdpContainer.din(),    100 ether);
        assertEq(liquidator.joy(),      0 ether);

        warp(1 days);

        assertEq(cdpContainer.tab(cdp), 105 ether);
        assertEq(cdpContainer.rap(cdp),   5.25 ether);

        assertEq(cdpContainer.din(),    105 ether);
        assertEq(liquidator.joy(),      5 ether);
    }
    function testFeeStabilityFeeDraw() public {
        var cdp = governanceFeeSetup();
        warp(1 days);
        assertEq(cdpContainer.tab(cdp), 105 ether);
        cdpContainer.withdrawDai(cdp, 100 ether);
        assertEq(cdpContainer.tab(cdp), 205 ether);
    }
    function testFeeStabilityFeeCalcFromRap() public {
        var cdp = governanceFeeSetup();

        assertEq(cdpContainer.tab(cdp), 100.00 ether);
        assertEq(cdpContainer.rap(cdp),   0.00 ether);
        warp(1 days);
        assertEq(cdpContainer.tab(cdp), 105.00 ether);
        assertEq(cdpContainer.rap(cdp),   5.25 ether);
    }
    function testFeeStabilityFeeWipeAll() public {
        var cdp = governanceFeeSetup();
        warp(1 days);

        var wad = cdpContainer.tab(cdp);
        assertEq(wad, 105 ether);
        var owe = cdpContainer.rap(cdp);
        assertEq(owe, 5.25 ether);

        var ( , , outstandingDebtAndStabilityFees, ire) = cdpContainer.cdps(cdp);
        assertEq(outstandingDebtAndStabilityFees, 100 ether);
        assertEq(ire, 100 ether);
        assertEq(rdiv(wad, cdpContainer.chi()), outstandingDebtAndStabilityFees);
        assertEq(rdiv(add(wad, owe), cdpContainer.rhi()), ire);

        dai.mint(5 ether);  // need to magic up some extra dai to pay stabilityFee27

        assertEq(cdpContainer.rap(cdp), 5.25 ether);
        assertEq(mkr.balanceOf(this), 100 ether);
        cdpContainer.depositDai(cdp, 105 ether);
        assertEq(cdpContainer.rap(cdp), 0 ether);
        assertEq(mkr.balanceOf(this), 89.5 ether);
    }
}

contract AxeTest is DaiTestBase {
    function axeSetup() public returns (bytes32) {
        mom.setCap(1000 ether);
        mark(1 ether);
        mom.setMat(ray(2 ether));       // require 200% collat
        cdpContainer.buyPethWithWeth(20 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 20 ether);
        cdpContainer.withdrawDai(cdp, 10 ether);       // 200% collateralisation

        return cdp;
    }
    function testAxeBite1() public {
        var cdp = axeSetup();

        mom.setAxe(ray(1.5 ether));
        mom.setMat(ray(2.1 ether));

        assertEq(cdpContainer.getPethCollateral(cdp), 20 ether);
        cdpContainer.marginCall(cdp);
        assertEq(cdpContainer.getPethCollateral(cdp), 5 ether);
    }
    function testAxeBite2() public {
        var cdp = axeSetup();

        mom.setAxe(ray(1.5 ether));
        mark(0.8 ether);    // collateral value 20 -> 16

        assertEq(cdpContainer.getPethCollateral(cdp), 20 ether);
        cdpContainer.marginCall(cdp);
        assertEq(cdpContainer.getPethCollateral(cdp), 1.25 ether);  // (1 / 0.8)
    }
    function testAxeBiteParity() public {
        var cdp = axeSetup();

        mom.setAxe(ray(1.5 ether));
        mark(0.5 ether);    // collateral value 20 -> 10

        assertEq(cdpContainer.getPethCollateral(cdp), 20 ether);
        cdpContainer.marginCall(cdp);
        assertEq(cdpContainer.getPethCollateral(cdp), 0 ether);
    }
    function testAxeBiteUnder() public {
        var cdp = axeSetup();

        mom.setAxe(ray(1.5 ether));
        mark(0.4 ether);    // collateral value 20 -> 8

        assertEq(cdpContainer.getPethCollateral(cdp), 20 ether);
        cdpContainer.marginCall(cdp);
        assertEq(cdpContainer.getPethCollateral(cdp), 0 ether);
    }
    function testZeroAxeCage() public {
        var cdp = axeSetup();

        mom.setAxe(ray(1 ether));

        assertEq(cdpContainer.getPethCollateral(cdp), 20 ether);
        top.triggerGlobalSettlement();
        cdpContainer.marginCall(cdp);
        liquidator.vent();
        top.flow();
        assertEq(cdpContainer.getPethCollateral(cdp), 10 ether);
    }
    function testAxeCage() public {
        var cdp = axeSetup();

        mom.setAxe(ray(1.5 ether));

        assertEq(cdpContainer.getPethCollateral(cdp), 20 ether);
        top.triggerGlobalSettlement();
        cdpContainer.marginCall(cdp);
        liquidator.vent();
        top.flow();
        assertEq(cdpContainer.getPethCollateral(cdp), 10 ether);
    }
}

contract DustTest is DaiTestBase {
    function testFailLockUnderDust() public {
        cdpContainer.buyPethWithWeth(1 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 0.0049 ether);
    }
    function testFailFreeUnderDust() public {
        cdpContainer.buyPethWithWeth(1 ether);
        var cdp = cdpContainer.open();
        cdpContainer.depositPeth(cdp, 1 ether);
        cdpContainer.withdrawPeth(cdp, 0.995 ether);
    }
}
