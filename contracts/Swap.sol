// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import "./interfaces/traderjoe/ILBRouter.sol";
import "./interfaces/traderjoe/IWNATIVE.sol";
import "./libraries/TokenHelper.sol";
import "./interfaces/traderjoe/IJoeFactory.sol";
import "./interfaces/traderjoe/ILBFactory.sol";
import "./interfaces/traderjoe/ILBLegacyFactory.sol";
import "./interfaces/traderjoe/IJoePair.sol";
import "./interfaces/traderjoe/ILBLegacyRouter.sol";
import "./libraries/JoeLibrary.sol";



contract Swap is Ownable {
    using SafeERC20 for IERC20;
    using TokenHelper for IWNATIVE;
    using JoeLibrary for uint256;

    address public immutable routerv2;
    IWNATIVE public immutable wnative;
    ILBFactory private immutable factory;
    ILBLegacyFactory private immutable legacyFactory;
    IJoeFactory public immutable factoryV1;
    ILBLegacyRouter private immutable legacyRouter;
    uint256 public constant INVERSE_BASIS_POINT = 1e4;
    uint256 public fee = 50; // 0.5% fee

    constructor (
        address _router02,
        IWNATIVE _wnative,
        IJoeFactory _factoryV1,
        ILBFactory _factory,
        ILBLegacyFactory _legacyFactory,
        ILBLegacyRouter _legacyRouter
    ) Ownable() {
        routerv2 = _router02;
        wnative = _wnative;
        factoryV1 = _factoryV1;
        factory = _factory;
        legacyFactory = _legacyFactory;
        legacyRouter = _legacyRouter;
    }

    // **** OWNER FUNCTION ****

    function setFee(uint256 _fee) external onlyOwner returns(bool) {
        fee = _fee;
        return true;
    }

    function withdraw(address token, uint256 amount, address to) external onlyOwner() returns(bool) {
        if(token == address(0)) {
            _wnativeDepositAndTransfer(to, amount);
            return true;
        }
        else {
            IERC20(token).safeTransfer(to, amount);
            return true;
        }
    }

    /**
     * @notice Simulate a swap in
     * @param pair The address of the LBPair
     * @param amountOut The amount of token to receive
     * @param swapForY Whether you swap X for Y (true), or Y for X (false)
     * @return amountIn The amount of token to send in order to receive amountOut token
     * @return amountOutLeft The amount of token Out that can't be returned due to a lack of liquidity
     * @return _fee The amount of fees paid in token sent
     */
    function getSwapIn(ILBPair pair, uint128 amountOut, bool swapForY)
        public
        view
        returns (uint128 amountIn, uint128 amountOutLeft, uint128 _fee)
    {
        (amountIn, amountOutLeft, _fee) = pair.getSwapIn(amountOut, swapForY);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair

    /**
     * @notice Swaps exact tokens for tokens while performing safety checks
     * @param amountIn The amount of token to send
     * @param amountOutMin The min amount of token to receive
     * @param path The path of the swap
     * @param to The address of the recipient
     * @param deadline The deadline of the tx
     * @return amountOut Output amount of the swap
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        ILBRouter.Path memory path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        uint256 feeAmount = amountIn * fee / INVERSE_BASIS_POINT;
        uint256 amountInAferFee = amountIn - feeAmount;

        path.tokenPath[0].safeTransferFrom(msg.sender, address(this), amountIn);
        path.tokenPath[0].approve(routerv2, amountIn);
        amountOut = ILBRouter(routerv2).swapExactTokensForTokens(amountInAferFee, amountOutMin, path, to, deadline);
    }

    /**
     * @notice Swaps exact tokens for NATIVE while performing safety checks
     * @param amountIn The amount of token to send
     * @param amountOutMinNATIVE The min amount of NATIVE to receive
     * @param path The path of the swap
     * @param to The address of the recipient
     * @param deadline The deadline of the tx
     * @return amountOut Output amount of the swap
     */
    function swapExactTokensForNATIVE(
        uint256 amountIn,
        uint256 amountOutMinNATIVE,
        ILBRouter.Path memory path,
        address payable to,
        uint256 deadline
    ) external returns (uint256 amountOut) {

        uint256 feeAmount = amountIn * fee / INVERSE_BASIS_POINT;
        uint256 amountInAferFee = amountIn - feeAmount;

        path.tokenPath[0].safeTransferFrom(msg.sender, address(this), amountIn);
        path.tokenPath[0].approve(routerv2, amountIn);
        amountOut = ILBRouter(routerv2).swapExactTokensForNATIVE(amountInAferFee, amountOutMinNATIVE, path, to, deadline);
    }

    /**
     * @notice Swaps exact NATIVE for tokens while performing safety checks
     * @param amountOutMin The min amount of token to receive
     * @param path The path of the swap
     * @param to The address of the recipient
     * @param deadline The deadline of the tx
     * @return amountOut Output amount of the swap
     */
    function swapExactNATIVEForTokens(uint256 amountOutMin, ILBRouter.Path memory path, address to, uint256 deadline)
        external
        payable
        returns (uint256 amountOut)
    {
        uint256 feeAmount = msg.value * fee / INVERSE_BASIS_POINT;
        uint256 amountInAferFee = msg.value - feeAmount;

        amountOut = ILBRouter(routerv2).swapExactNATIVEForTokens{value: amountInAferFee}(amountOutMin, path, to, deadline);
    }

    /**
     * @notice Swaps tokens for exact tokens while performing safety checks
     * @param amountOut The amount of token to receive
     * @param amountInMax The max amount of token to send
     * @param path The path of the swap
     * @param to The address of the recipient
     * @param deadline The deadline of the tx
     * @return amountsIn Input amounts of the swap
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        ILBRouter.Path memory path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amountsIn) {
        address[] memory pairs = _getPairs(path.pairBinSteps, path.versions, path.tokenPath);

        amountsIn = _getAmountsIn(path.versions, pairs, path.tokenPath, amountOut);

        uint256 amountInAferFee = amountsIn[0] * INVERSE_BASIS_POINT / ( INVERSE_BASIS_POINT - fee);

        require(amountInAferFee <= amountInMax, "SWAP: Insufficient swap-in balance");

        path.tokenPath[0].safeTransferFrom(msg.sender, address(this), amountInAferFee);
        path.tokenPath[0].approve(routerv2, amountsIn[0]);
        ILBRouter(routerv2).swapTokensForExactTokens(amountOut, amountInMax, path, to, deadline);

    }

    /**
     * @notice Swaps tokens for exact NATIVE while performing safety checks
     * @param amountNATIVEOut The amount of NATIVE to receive
     * @param amountInMax The max amount of token to send
     * @param path The path of the swap
     * @param to The address of the recipient
     * @param deadline The deadline of the tx
     * @return amountsIn path amounts for every step of the swap
     */
    function swapTokensForExactNATIVE(
        uint256 amountNATIVEOut,
        uint256 amountInMax,
        ILBRouter.Path memory path,
        address payable to,
        uint256 deadline
    ) external returns (uint256[] memory amountsIn) {

        address[] memory pairs = _getPairs(path.pairBinSteps, path.versions, path.tokenPath);
        amountsIn = _getAmountsIn(path.versions, pairs, path.tokenPath, amountNATIVEOut);

        uint256 amountInAferFee = amountsIn[0] * INVERSE_BASIS_POINT / ( INVERSE_BASIS_POINT - fee);

        require(amountInAferFee <= amountInMax, "SWAP: Insufficient swap-in balance");

        path.tokenPath[0].safeTransferFrom(msg.sender, address(this), amountInAferFee);
        path.tokenPath[0].approve(routerv2, amountsIn[0]);
        ILBRouter(routerv2).swapTokensForExactNATIVE(amountNATIVEOut, amountInMax, path, to, deadline);
    }

    /**
     * @notice Swaps NATIVE for exact tokens while performing safety checks
     * @dev Will refund any NATIVE amount sent in excess to `msg.sender`
     * @param amountOut The amount of tokens to receive
     * @param path The path of the swap
     * @param to The address of the recipient
     * @param deadline The deadline of the tx
     * @return amountsIn path amounts for every step of the swap
     */
    function swapNATIVEForExactTokens(uint256 amountOut, ILBRouter.Path memory path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amountsIn)
    {

        address[] memory pairs = _getPairs(path.pairBinSteps, path.versions, path.tokenPath);
        amountsIn = _getAmountsIn(path.versions, pairs, path.tokenPath, amountOut);

        uint256 amountInAferFee = amountsIn[0] * INVERSE_BASIS_POINT / ( INVERSE_BASIS_POINT - fee);

        require(amountInAferFee <= msg.value, "SWAP: Insufficient swap-in balance");

        ILBRouter(routerv2).swapNATIVEForExactTokens{value: amountsIn[0]}(amountOut, path, to, deadline);
    }

    /**
     * @notice Helper function to return the amounts in
     * @param versions The list of versions (V1, V2 or V2_1)
     * @param pairs The list of pairs
     * @param tokenPath The swap path
     * @param amountOut The amount out
     * @return amountsIn The list of amounts in
     */
    function _getAmountsIn(
        ILBRouter.Version[] memory versions,
        address[] memory pairs,
        IERC20[] memory tokenPath,
        uint256 amountOut
    ) private view returns (uint256[] memory amountsIn) {
        amountsIn = new uint256[](tokenPath.length);
        // Avoid doing -1, as `pairs.length == pairBinSteps.length-1`
        amountsIn[pairs.length] = amountOut;

        for (uint256 i = pairs.length; i != 0; i--) {
            IERC20 token = tokenPath[i - 1];
            ILBRouter.Version version = versions[i - 1];
            address pair = pairs[i - 1];

            if (version == ILBRouter.Version.V1) {
                (uint256 reserveIn, uint256 reserveOut,) = IJoePair(pair).getReserves();
                if (token > tokenPath[i]) {
                    (reserveIn, reserveOut) = (reserveOut, reserveIn);
                }

                uint256 amountOut_ = amountsIn[i];
                amountsIn[i - 1] = uint128(amountOut_.getAmountIn(reserveIn, reserveOut));
            } else if (version == ILBRouter.Version.V2) {
                (amountsIn[i - 1],) = legacyRouter.getSwapIn(
                    ILBLegacyPair(pair), uint128(amountsIn[i]), ILBLegacyPair(pair).tokenX() == token
                );
            } else {
                (amountsIn[i - 1],,) =
                    getSwapIn(ILBPair(pair), uint128(amountsIn[i]), ILBPair(pair).getTokenX() == token);
            }
        }
    }

    /**
     * @notice Helper function to return a list of pairs
     * @param pairBinSteps The list of bin steps
     * @param versions The list of versions (V1, V2 or V2_1)
     * @param tokenPath The swap path using the binSteps following `pairBinSteps`
     * @return pairs The list of pairs
     */
    function _getPairs(uint256[] memory pairBinSteps,   ILBRouter.Version[] memory versions, IERC20[] memory tokenPath)
        private
        view
        returns (address[] memory pairs)
    {
        pairs = new address[](pairBinSteps.length);

        IERC20 token;
        IERC20 tokenNext = tokenPath[0];
        unchecked {
            for (uint256 i; i < pairs.length; ++i) {
                token = tokenNext;
                tokenNext = tokenPath[i + 1];

                pairs[i] = _getPair(token, tokenNext, pairBinSteps[i], versions[i]);
            }
        }
    }

    /**
     * @notice Helper function to return the address of the pair (v1 or v2, according to `binStep`)
     * @dev Revert if the pair is not created yet
     * @param tokenX The address of the tokenX
     * @param tokenY The address of the tokenY
     * @param binStep The bin step of the LBPair
     * @param version The version of the LBPair
     * @return pair The address of the pair of binStep `binStep`
     */
    function _getPair(IERC20 tokenX, IERC20 tokenY, uint256 binStep, ILBRouter.Version version)
        private
        view
        returns (address pair)
    {
        if (version == ILBRouter.Version.V1) {
            pair = factoryV1.getPair(address(tokenX), address(tokenY));
            if (pair == address(0)) revert ILBRouter.LBRouter__PairNotCreated(address(tokenX), address(tokenY), binStep);
        } else {
            pair = address(_getLBPairInformation(tokenX, tokenY, binStep, version));
        }
    }

    /**
     * @notice Helper function to return the address of the LBPair
     * @dev Revert if the pair is not created yet
     * @param tokenX The address of the tokenX
     * @param tokenY The address of the tokenY
     * @param binStep The bin step of the LBPair
     * @param version The version of the LBPair
     * @return lbPair The address of the LBPair
     */
    function _getLBPairInformation(IERC20 tokenX, IERC20 tokenY, uint256 binStep, ILBRouter.Version version)
        private
        view
        returns (address lbPair)
    {
        if (version == ILBRouter.Version.V2) {
            lbPair = address(legacyFactory.getLBPairInformation(tokenX, tokenY, binStep).LBPair);
        } else {
            lbPair = address(factory.getLBPairInformation(tokenX, tokenY, binStep).LBPair);
        }

        if (lbPair == address(0)) {
            revert ILBRouter.LBRouter__PairNotCreated(address(tokenX), address(tokenY), binStep);
        }
    }

    /**
     * @notice Helper function to deposit and transfer _wnative
     * @param to The address of the recipient
     * @param amount The NATIVE amount to wrap
     */
    function _wnativeDepositAndTransfer(address to, uint256 amount) private {
        wnative.deposit{value: amount}();
        wnative.safeTransfer(to, amount);
    }


}
