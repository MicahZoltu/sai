pragma solidity ^0.4.18;

import "ds-test/test.sol";
import './factory.sol';

contract BinTest is DSTest {
    WethFactory wethFactory;
    VoxFactory voxFactory;
    CdpContainerFactory cdpContainerFactory;
    LiquidatorFactory liquidatorFactory;
    TopFactory topFactory;
    MomFactory momFactory;
    DadFactory dadFactory;

    DaiFactory daiFactory;

    DSToken weth;
    DSToken mkr;
    DSValue usdPerEth;
    DSValue daiPerMaker;
    address pit;

    DSRoles authority;

    function setUp() public {
        wethFactory = new WethFactory();
        voxFactory = new VoxFactory();
        cdpContainerFactory = new CdpContainerFactory();
        liquidatorFactory = new LiquidatorFactory();
        topFactory = new TopFactory();
        momFactory = new MomFactory();
        dadFactory = new DadFactory();

        uint startGas = msg.gas;
        daiFactory = new DaiFactory(wethFactory, voxFactory, cdpContainerFactory, liquidatorFactory, topFactory, momFactory, dadFactory);
        uint endGas = msg.gas;
        log_named_uint('Deploy DaiFactory', startGas - endGas);

        weth = new DSToken('WETH');
        mkr = new DSToken('MKR');
        usdPerEth = new DSValue();
        daiPerMaker = new DSValue();
        pit = address(0x123);
        authority = new DSRoles();
        authority.setRootUser(this, true);
    }

    function testMake() public {
        uint startGas = msg.gas;
        daiFactory.makeTokens();
        uint endGas = msg.gas;
        log_named_uint('Make Tokens', startGas - endGas);

        startGas = msg.gas;
        daiFactory.makeVoxCdpContainer(weth, mkr, usdPerEth, daiPerMaker, pit);
        endGas = msg.gas;
        log_named_uint('Make Vox CdpContainer', startGas - endGas);

        startGas = msg.gas;
        daiFactory.makeTapTop();
        endGas = msg.gas;
        log_named_uint('Make Tap Top', startGas - endGas);

        startGas = msg.gas;
        daiFactory.configParams();
        endGas = msg.gas;
        log_named_uint('Config Params', startGas - endGas);

        startGas = msg.gas;
        daiFactory.verifyParams();
        endGas = msg.gas;
        log_named_uint('Verify Params', startGas - endGas);

        startGas = msg.gas;
        daiFactory.configAuth(authority);
        endGas = msg.gas;
        log_named_uint('Config Auth', startGas - endGas);
    }

    function testFailStep() public {
        daiFactory.makeTokens();
        daiFactory.makeTokens();
    }

    function testFailStep2() public {
        daiFactory.makeTokens();
        daiFactory.makeTapTop();
    }

    function testFailStep3() public {
        daiFactory.makeTokens();
        daiFactory.makeVoxCdpContainer(weth, mkr, usdPerEth, daiPerMaker, pit);
        daiFactory.makeTapTop();
        daiFactory.makeVoxCdpContainer(weth, mkr, usdPerEth, daiPerMaker, pit);
    }

    function testFailStep4() public {
        daiFactory.makeTokens();
        daiFactory.makeVoxCdpContainer(weth, mkr, usdPerEth, daiPerMaker, pit);
        daiFactory.makeTapTop();
        daiFactory.configAuth(authority);
        daiFactory.makeTokens();
    }
}
