/// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

import {svg} from "src/lib/SVG.sol";
import {Timestamp} from "src/lib/Timestamp.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract LinearVestingCard {
    // solhint-disable quotes

    // ========== DATA STRUCTURES ========== //

    struct Info {
        uint256 tokenId;
        address baseToken;
        string baseTokenSymbol;
        uint48 start;
        uint48 expiry;
        uint256 supply;
    }

    // ========== STATE VARIABLES ========== //

    string internal constant _TEXT_STYLE =
        'font-family="\'Menlo\', monospace" fill="white" text-anchor="middle"';
    string internal constant _NULL = "";
    string internal _addrString;

    string internal constant _COLOR_BLUE = "rgb(110, 148, 240)";
    string internal constant _COLOR_LIGHT_BLUE = "rgb(118, 189, 242)";
    string internal constant _COLOR_GREEN = "rgb(206, 244, 117)";
    string internal constant _COLOR_YELLOW_GREEN = "rgb(243, 244, 189)";
    string internal constant _COLOR_YELLOW = "rgb(243, 244, 189)";
    string internal constant _COLOR_ORANGE = "rgb(246, 172, 84)";
    string internal constant _COLOR_RED = "rgb(242, 103, 64)";

    // ========== CONSTRUCTOR ========== //

    constructor() {
        _addrString = Strings.toHexString(address(this));
    }

    // ========== ATTRIBUTES ========== //

    function _attributes(Info memory tokenInfo) internal view returns (string memory) {
        return string.concat(
            '[{"trait_type":"Token ID","value":"',
            Strings.toString(tokenInfo.tokenId),
            '"},',
            '{"trait_type":"Base Token","value":"',
            Strings.toHexString(tokenInfo.baseToken),
            '"},',
            '{"trait_type":"Base Token Symbol", "value":"',
            tokenInfo.baseTokenSymbol,
            '"},',
            '{"trait_type":"Vesting Start","display_type":"date","value":"',
            Strings.toString(tokenInfo.start),
            '"},',
            '{"trait_type":"Vesting End","display_type":"date","value":"',
            Strings.toString(tokenInfo.expiry),
            '"},',
            '{"trait_type":"Total Supply","value":"',
            Strings.toString(tokenInfo.supply),
            '"}]'
        );
    }

    // ========== RENDERER ========== //
    function _render(Info memory tokenInfo) internal view returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 290 500">',
            svg.el(
                "defs",
                _NULL,
                string.concat(
                    _fullGradient(),
                    _fullGradient90(),
                    _fullGradientReverse90(),
                    _blueGreenGradient()
                )
            ),
            svg.rect(
                'x="0" y="0" width="290" height="500" fill="rgb(30, 30, 30)" rx="25" ry="25"', _NULL
            ),
            svg.rect(
                'x="8" y="8" width="274" height="484" fill="none" stroke="url(#fullGradient)" stroke-width="2" rx="20" ry="20"',
                _NULL
            ),
            _title(tokenInfo.baseTokenSymbol),
            _progressBar(uint256(tokenInfo.start), uint256(tokenInfo.expiry)),
            _progressLabels(tokenInfo.start, tokenInfo.expiry),
            _logo(),
            _identifier(tokenInfo.tokenId),
            "</svg>"
        );
    }

    // ========== COMPONENTS ========== //

    function _title(string memory symbol) internal pure returns (string memory) {
        return string.concat(
            svg.text(string.concat('x="145" y="40" font-size="20" ', _TEXT_STYLE), "Linear Vesting"),
            svg.text(string.concat('x="145" y="100" font-size="56" ', _TEXT_STYLE), symbol)
        );
    }

    function _logo() internal pure returns (string memory) {
        return string.concat(
            svg.rect(
                'x="143" y="240" width="6" height="125" fill="url(#fullGradientReverse90)"', _NULL
            ),
            svg.rect(
                'x="79" y="246" width="6" height="125" fill="url(#fullGradient90)" transform="rotate(-60 145 250)"',
                _NULL
            ),
            svg.rect(
                'x="206" y="244" width="6" height="125" fill="url(#fullGradient90)" transform="rotate(60 145 250)"',
                _NULL
            )
        );
    }

    function _identifier(uint256 tokenId) internal view returns (string memory) {
        return string.concat(
            svg.text(string.concat('x="145" y="460" font-size="10" ', _TEXT_STYLE), _addrString),
            svg.text(
                string.concat('x="145" y="480" font-size="10" ', _TEXT_STYLE),
                string.concat("ID: ", Strings.toString(tokenId))
            )
        );
    }

    function _progressBar(uint256 start, uint256 end) internal view returns (string memory) {
        uint256 currentTime = block.timestamp; // 1717200000 + 70 * 86400;

        string memory startBar;
        string memory endBar;
        uint256 progress;
        {
            bool started = start <= currentTime;

            progress = started ? (currentTime - start) * 100 / (end - start) : 0;
            // progress can be at most 100
            progress = progress > 100 ? 100 : progress;

            startBar = svg.line(
                string.concat(
                    'x1="60" y1="155" x2="60" y2="175" stroke="',
                    started ? _COLOR_BLUE : "grey",
                    '" stroke-width="6"'
                ),
                _NULL
            );

            endBar = svg.line(
                string.concat(
                    'x1="230" y1="155" x2="230" y2="175" stroke="',
                    progress == 100 ? _COLOR_GREEN : "grey",
                    '" stroke-width="6"'
                ),
                _NULL
            );
        }

        uint256 len = (168 * progress) / 100;
        string memory current = Strings.toString(62 + len);

        string memory progressLine = svg.line(
            string.concat(
                'x1="62" y1="165" x2="',
                current,
                '" y2="165" stroke="url(#blueGreenGradient)" stroke-width="6"'
            ),
            _NULL
        );

        string memory progressCircle = svg.circle(
            string.concat('cx="', current, '" cy="165" r="6" fill="url(#blueGreenGradient)"'), _NULL
        );

        string memory shadowLine = svg.line(
            string.concat('x1="63" y1="165" x2="230" y2="165" stroke="grey" stroke-width="4"'),
            _NULL
        );

        return svg.g(
            _NULL,
            string.concat(
                startBar,
                shadowLine,
                progressLine,
                progress < 15 ? "" : _animateLine(len),
                endBar,
                progress < 5 || progress > 95 ? "" : progressCircle
            )
        );
    }

    function _animateLine(uint256 len) internal pure returns (string memory) {
        return svg.rect(
            string.concat(
                'x="62" y="161" width="12" height="8" fill="url(#blueGreenGradient)" rx="4" ry="4"'
            ),
            svg.el(
                "animate",
                string.concat(
                    'attributeName="x" values="62;',
                    Strings.toString(62 + len - 16),
                    ';" dur="',
                    Strings.toString(((5 * len) / 168) + 1),
                    's" repeatCount="indefinite"'
                ),
                _NULL
            )
        );
    }

    function _progressLabels(uint48 start_, uint48 expiry_) internal pure returns (string memory) {
        (string memory start, string memory expiry) = _getTimeStrings(start_, expiry_);

        return string.concat(
            svg.text(string.concat('x="60" y="200" font-size="12" ', _TEXT_STYLE), start),
            svg.text(string.concat('x="230" y="200" font-size="12"', _TEXT_STYLE), expiry)
        );
    }

    // ========== COLOR GRADIENTS ========== //

    function _fullGradientStops() internal pure returns (string memory) {
        return string.concat(
            svg.gradientStop(2, _COLOR_BLUE, _NULL),
            svg.gradientStop(10, _COLOR_LIGHT_BLUE, _NULL),
            svg.gradientStop(32, _COLOR_GREEN, _NULL),
            svg.gradientStop(49, _COLOR_YELLOW_GREEN, _NULL),
            svg.gradientStop(52, _COLOR_YELLOW, _NULL),
            svg.gradientStop(79, _COLOR_ORANGE, _NULL),
            svg.gradientStop(100, _COLOR_RED, _NULL)
        );
    }

    function _fullGradientReverseStops() internal pure returns (string memory) {
        return string.concat(
            svg.gradientStop(2, _COLOR_RED, _NULL),
            svg.gradientStop(21, _COLOR_ORANGE, _NULL),
            svg.gradientStop(48, _COLOR_YELLOW, _NULL),
            svg.gradientStop(51, _COLOR_YELLOW_GREEN, _NULL),
            svg.gradientStop(68, _COLOR_GREEN, _NULL),
            svg.gradientStop(90, _COLOR_LIGHT_BLUE, _NULL),
            svg.gradientStop(100, _COLOR_BLUE, _NULL)
        );
    }

    function _fullGradient() internal pure returns (string memory) {
        return
            svg.linearGradient(string.concat(svg.prop("id", "fullGradient")), _fullGradientStops());
    }

    function _fullGradient90() internal pure returns (string memory) {
        return svg.linearGradient(
            string.concat(
                svg.prop("id", "fullGradient90"), svg.prop("gradientTransform", "rotate(90)")
            ),
            _fullGradientStops()
        );
    }

    function _fullGradientReverse90() internal pure returns (string memory) {
        return svg.linearGradient(
            string.concat(
                svg.prop("id", "fullGradientReverse90"), svg.prop("gradientTransform", "rotate(90)")
            ),
            _fullGradientReverseStops()
        );
    }

    function _blueGreenGradient() internal pure returns (string memory) {
        return svg.linearGradient(
            string.concat(
                svg.prop("id", "blueGreenGradient"), svg.prop("gradientUnits", "userSpaceOnUse")
            ),
            string.concat(
                svg.gradientStop(20, _COLOR_BLUE, _NULL),
                svg.gradientStop(40, _COLOR_LIGHT_BLUE, _NULL),
                svg.gradientStop(60, _COLOR_GREEN, _NULL)
            )
        );
    }

    // ========== UTILITIES ========== //

    function _getTimeStrings(
        uint48 start,
        uint48 end
    ) internal pure returns (string memory, string memory) {
        (string memory startYear, string memory startMonth, string memory startDay) =
            Timestamp.toPaddedString(start);
        (string memory endYear, string memory endMonth, string memory endDay) =
            Timestamp.toPaddedString(end);

        return (
            string.concat(startYear, "-", startMonth, "-", startDay),
            string.concat(endYear, "-", endMonth, "-", endDay)
        );
    }

    // ========== EXAMPLE ========== //
    // Used by hot-chain-svg during development.
    //
    // function example() external view returns (string memory) {
    //     Info memory info = Info({
    //         baseToken: address(0x1234567890123456789012345678901234567890),
    //         baseTokenSymbol: "XYZ",
    //         tokenId: 123_456,
    //         start: 1_717_200_000, // 2024-06-01
    //         expiry: 1_725_148_800 // 2024-09-01
    //     });
    //     return _render(info);
    // }
}
