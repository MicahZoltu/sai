/// cdpContainer.t.sol -- Unit tests for cdpContainer.sol

pragma solidity ^0.4.18;

import './cdpContainer.sol';
import './liquidator.sol';
import 'ds-guard/guard.sol';
import "ds-test/test.sol";

contract CdpContainerTest is DSTest, DSThing {
    address liquidator;
    DaiCdpContainer  cdpContainer;
    DaiVox  vox;

    DSGuard dad;

    DSValue usdPerEth;
    DSValue daiPerMaker;

    DSToken dai;
    DSToken sin;
    DSToken peth;
    DSToken weth;
    DSToken mkr;

    function setUp() public {
        dai = new DSToken("DAI");
        sin = new DSToken("SIN");
        peth = new DSToken("PETH");
        weth = new DSToken("WETH");
        mkr = new DSToken("MKR");
        usdPerEth = new DSValue();
        daiPerMaker = new DSValue();
        dad = new DSGuard();
        vox = new DaiVox(ONE_27);
        cdpContainer = new DaiCdpContainer(dai, sin, peth, weth, mkr, usdPerEth, daiPerMaker, vox, 0x123);
        liquidator = 0x456;
        cdpContainer.turn(liquidator);

        //Set whitelist authority
        peth.setAuthority(dad);

        //Permit cdpContainer to 'mint' and 'burn' PETH
        dad.permit(cdpContainer, peth, bytes4(keccak256('mint(address,uint256)')));
        dad.permit(cdpContainer, peth, bytes4(keccak256('burn(address,uint256)')));

        //Allow cdpContainer to mint, burn, and transfer weth/peth without approval
        weth.approve(cdpContainer);
        peth.approve(cdpContainer);
        dai.approve(cdpContainer);

        weth.mint(6 ether);

        //Verify initial token balances
        assertEq(weth.balanceOf(this), 6 ether);
        assertEq(weth.balanceOf(cdpContainer), 0 ether);
        assertEq(peth.totalSupply(), 0 ether);

        assert(!cdpContainer.off());
    }

    function testFailTurnAgain() public {
        cdpContainer.turn(0x789);
    }

    function testTotalCollateralizedWeth() public {
        assertEq(cdpContainer.wethLockedInPeth(), weth.balanceOf(cdpContainer));
        assertEq(cdpContainer.wethLockedInPeth(), 0 ether);
        weth.mint(75 ether);
        cdpContainer.buyPethWithWeth(72 ether);
        assertEq(cdpContainer.wethLockedInPeth(), weth.balanceOf(cdpContainer));
        assertEq(cdpContainer.wethLockedInPeth(), 72 ether);
    }

    function testPer() public {
        cdpContainer.buyPethWithWeth(5 ether);
        assertEq(peth.totalSupply(), 5 ether);
        assertEq(cdpContainer.wethPerPeth(), rdiv(5 ether, 5 ether));
    }

    function testUsdPerPeth() public {
        cdpContainer.usdPerEth().poke(bytes32(1 ether));
        assertEq(cdpContainer.usdPerEth().read(), bytes32(1 ether));
        assertEq(wmul(cdpContainer.wethPerPeth(), uint(cdpContainer.usdPerEth().read())), cdpContainer.usdPerPeth());
        cdpContainer.usdPerEth().poke(bytes32(5 ether));
        assertEq(cdpContainer.usdPerEth().read(), bytes32(5 ether));
        assertEq(wmul(cdpContainer.wethPerPeth(), uint(cdpContainer.usdPerEth().read())), cdpContainer.usdPerPeth());
    }

    function testGap() public {
        assertEq(cdpContainer.wethToPethSpread18(), ONE_18);
        cdpContainer.mold('wethToPethSpread18', 2 ether);
        assertEq(cdpContainer.wethToPethSpread18(), 2 ether);
        cdpContainer.mold('wethToPethSpread18', wmul(ONE_18, 10 ether));
        assertEq(cdpContainer.wethToPethSpread18(), wmul(ONE_18, 10 ether));
    }

    function testAsk() public {
        assertEq(cdpContainer.wethPerPeth(), ONE_27);
        assertEq(cdpContainer.ask(3 ether), rmul(3 ether, wmul(ONE_27, cdpContainer.wethToPethSpread18())));
        assertEq(cdpContainer.ask(wmul(ONE_18, 33)), rmul(wmul(ONE_18, 33), wmul(ONE_27, cdpContainer.wethToPethSpread18())));
    }

    function testBid() public {
        assertEq(cdpContainer.wethPerPeth(), ONE_27);
        assertEq(cdpContainer.bid(4 ether), rmul(4 ether, wmul(cdpContainer.wethPerPeth(), sub(2 * ONE_18, cdpContainer.wethToPethSpread18()))));
        assertEq(cdpContainer.bid(wmul(5 ether,3333333)), rmul(wmul(5 ether,3333333), wmul(cdpContainer.wethPerPeth(), sub(2 * ONE_18, cdpContainer.wethToPethSpread18()))));
    }

    function testJoin() public {
        cdpContainer.buyPethWithWeth(3 ether);
        assertEq(weth.balanceOf(this), 3 ether);
        assertEq(weth.balanceOf(cdpContainer), 3 ether);
        assertEq(peth.totalSupply(), 3 ether);
        cdpContainer.buyPethWithWeth(1 ether);
        assertEq(weth.balanceOf(this), 2 ether);
        assertEq(weth.balanceOf(cdpContainer), 4 ether);
        assertEq(peth.totalSupply(), 4 ether);
    }

    function testExit() public {
        weth.mint(10 ether);
        assertEq(weth.balanceOf(this), 16 ether);

        cdpContainer.buyPethWithWeth(12 ether);
        assertEq(weth.balanceOf(cdpContainer), 12 ether);
        assertEq(weth.balanceOf(this), 4 ether);
        assertEq(peth.totalSupply(), 12 ether);

        cdpContainer.sellPethForWeth(3 ether);
        assertEq(weth.balanceOf(cdpContainer), 9 ether);
        assertEq(weth.balanceOf(this), 7 ether);
        assertEq(peth.totalSupply(), 9 ether);

        cdpContainer.sellPethForWeth(7 ether);
        assertEq(weth.balanceOf(cdpContainer), 2 ether);
        assertEq(weth.balanceOf(this), 14 ether);
        assertEq(peth.totalSupply(), 2 ether);
    }

    function testCage() public {
        cdpContainer.buyPethWithWeth(5 ether);
        assertEq(weth.balanceOf(cdpContainer), 5 ether);
        assertEq(weth.balanceOf(this), 1 ether);
        assertEq(peth.totalSupply(), 5 ether);
        assert(!cdpContainer.off());

        cdpContainer.triggerGlobalSettlement(cdpContainer.wethPerPeth(), 5 ether);
        assertEq(weth.balanceOf(cdpContainer), 0 ether);
        assertEq(weth.balanceOf(liquidator), 5 ether);
        assertEq(peth.totalSupply(), 5 ether);
        assert(cdpContainer.off());
    }

    function testFlow() public {
        cdpContainer.buyPethWithWeth(1 ether);
        cdpContainer.triggerGlobalSettlement(cdpContainer.wethPerPeth(), 1 ether);
        assert(cdpContainer.off());
        assert(!cdpContainer.out());
        cdpContainer.flow();
        assert(cdpContainer.out());
    }
}
