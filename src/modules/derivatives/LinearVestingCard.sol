/// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

import {svg} from "src/lib/SVG.sol";
import {Timestamp} from "src/lib/Timestamp.sol";
// import {LibString} from "lib/solady/src/utils/LibString.sol";
import {Strings as LibString} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract LinearVestingCard {
    // ========== DATA STRUCTURES ========== //

    struct Info {
        uint256 tokenId;
        string baseAssetSymbol;
        uint48 start;
        uint48 expiry;
    }

    struct Colors {
        string blue;
        string lightBlue;
        string green;
        string yellowGreen;
        string yellow;
        string orange;
        string red;
    }

    // ========== STATE VARIABLES ========== //

    string internal constant TEXT_STYLE =
        'font-family="\'Menlo\', monospace" fill="white" text-anchor="middle"';
    string internal constant NULL = "";
    string internal ADDR_STRING;

    Colors internal colors;

    // ========== CONSTRUCTOR ========== //

    constructor() {
        colors = Colors({
            blue: "rgb(110, 148, 240)",
            lightBlue: "rgb(118, 189, 242)",
            green: "rgb(206, 244, 117)",
            yellowGreen: "rgb(243, 244, 189)",
            yellow: "rgb(243, 244, 189)",
            orange: "rgb(246, 172, 84)",
            red: "rgb(242, 103, 64)"
        });

        ADDR_STRING = LibString.toHexString(address(this));
    }

    // ========== RENDERER ========== //
    function render(Info memory tokenInfo) internal view returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 290 500">',
            svg.el(
                "defs",
                NULL,
                string.concat(
                    fullGradient(), fullGradient90(), fullGradientReverse90(), blueGreenGradient()
                )
            ),
            svg.rect(
                // string.concat(
                //     svg.prop('x', '0'),
                //     svg.prop('y', '0'),
                //     svg.prop('width', '290'),
                //     svg.prop('height', '500'),
                //     svg.prop('fill', 'rgb(30, 30, 30)'),
                //     svg.prop('rx', '25'),
                //     svg.prop('ry', '25')
                // ),
                'x="0" y="0" width="290" height="500" fill="rgb(30, 30, 30)" rx="25" ry="25"',
                NULL
            ),
            svg.rect(
                // string.concat(
                //     svg.prop('x', '8'),
                //     svg.prop('y', '8'),
                //     svg.prop('width', '274'),
                //     svg.prop('height', '484'),
                //     svg.prop('fill', 'none'),
                //     svg.prop('stroke', "url('#fullGradient')"),
                //     svg.prop('stroke-width', '2'),
                //     svg.prop('rx', '20'),
                //     svg.prop('ry', '20')
                // ),
                'x="8" y="8" width="274" height="484" fill="none" stroke="url(#fullGradient)" stroke-width="2" rx="20" ry="20"',
                NULL
            ),
            title(tokenInfo.baseAssetSymbol),
            progressBar(uint256(tokenInfo.start), uint256(tokenInfo.expiry)),
            progressLabels(tokenInfo.start, tokenInfo.expiry),
            logo(),
            identifier(tokenInfo.tokenId),
            "</svg>"
        );
    }

    // ========== COMPONENTS ========== //

    function title(string memory symbol) internal pure returns (string memory) {
        return string.concat(
            svg.text(
                // string.concat(
                //     svg.prop('x', '145'),
                //     svg.prop('y', '40'),
                //     svg.prop('font-size', '20'),
                //     TEXT_STYLE
                // ),
                string.concat('x="145" y="40" font-size="20" ', TEXT_STYLE),
                "Linear Vesting"
            ),
            svg.text(
                // string.concat(
                //     svg.prop('x', '145'),
                //     svg.prop('y', '100'),
                //     svg.prop('font-size', '56'),
                //     TEXT_STYLE
                // ),
                string.concat('x="145" y="100" font-size="56" ', TEXT_STYLE),
                symbol
            )
        );
    }

    function logo() internal pure returns (string memory) {
        return string.concat(
            svg.rect(
                // string.concat(
                //     svg.prop('x', '143'),
                //     svg.prop('y', '240'),
                //     svg.prop('width', '6'),
                //     svg.prop('height', '125'),
                //     svg.prop('fill', "url('#fullGradientReverse90')")
                // ),
                'x="143" y="240" width="6" height="125" fill="url(#fullGradientReverse90)"',
                NULL
            ),
            svg.rect(
                // string.concat(
                //     svg.prop('x', '79'),
                //     svg.prop('y', '246'),
                //     svg.prop('width', '6'),
                //     svg.prop('height', '125'),
                //     svg.prop('fill', "url('#fullGradient90')"),
                //     svg.prop('transform', 'rotate(-60 145 250)')
                // ),
                'x="79" y="246" width="6" height="125" fill="url(#fullGradient90)" transform="rotate(-60 145 250)"',
                NULL
            ),
            svg.rect(
                // string.concat(
                //     svg.prop('x', '206'),
                //     svg.prop('y', '244'),
                //     svg.prop('width', '6'),
                //     svg.prop('height', '125'),
                //     svg.prop('fill', "url('#fullGradient90')"),
                //     svg.prop('transform', 'rotate(60 145 250)')
                // ),
                'x="206" y="244" width="6" height="125" fill="url(#fullGradient90)" transform="rotate(60 145 250)"',
                NULL
            )
        );
    }

    function identifier(uint256 tokenId) internal view returns (string memory) {
        return string.concat(
            svg.text(
                // string.concat(
                //     svg.prop('x', '145'),
                //     svg.prop('y', '460'),
                //     svg.prop('font-size', '10'),
                //     TEXT_STYLE
                // ),
                string.concat('x="145" y="460" font-size="10" ', TEXT_STYLE),
                ADDR_STRING
            ),
            svg.text(
                // string.concat(
                //     svg.prop('x', '145'),
                //     svg.prop('y', '480'),
                //     svg.prop('font-size', '10'),
                //     TEXT_STYLE
                // ),
                string.concat('x="145" y="480" font-size="10" ', TEXT_STYLE),
                string.concat("ID: ", LibString.toString(tokenId))
            )
        );
    }

    function progressBar(uint256 start, uint256 end) internal view returns (string memory) {
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
                // string.concat(
                //     svg.prop('x1', '60'),
                //     svg.prop('y1', '155'),
                //     svg.prop('x2', '60'),
                //     svg.prop('y2', '175'),
                //     svg.prop('stroke', started ? colors.blue : 'grey'),
                //     svg.prop('stroke-width', '6')
                // ),
                string.concat(
                    'x1="60" y1="155" x2="60" y2="175" stroke="',
                    started ? colors.blue : "grey",
                    '" stroke-width="6"'
                ),
                NULL
            );

            endBar = svg.line(
                // string.concat(
                //     svg.prop('x1', '230'),
                //     svg.prop('y1', '155'),
                //     svg.prop('x2', '230'),
                //     svg.prop('y2', '175'),
                //     svg.prop('stroke', progress == 100 ? colors.green : 'grey'),
                //     svg.prop('stroke-width', '6')
                // ),
                string.concat(
                    'x1="230" y1="155" x2="230" y2="175" stroke="',
                    progress == 100 ? colors.green : "grey",
                    '" stroke-width="6"'
                ),
                NULL
            );
        }

        uint256 len = (168 * progress) / 100;
        string memory current = LibString.toString(62 + len);

        string memory progressLine = svg.line(
            // string.concat(
            //     svg.prop('x1', '62'),
            //     svg.prop('y1', '165'),
            //     svg.prop('x2', current),
            //     svg.prop('y2', '165'),
            //     svg.prop('stroke', "url('#blueGreenGradient')"),
            //     svg.prop('stroke-width', '6')
            // ),
            string.concat(
                'x1="62" y1="165" x2="',
                current,
                '" y2="165" stroke="url(#blueGreenGradient)" stroke-width="6"'
            ),
            NULL
        );

        string memory progressCircle = svg.circle(
            // string.concat(
            //     svg.prop('cx', current),
            //     svg.prop('cy', '165'),
            //     svg.prop('r', '6'),
            //     svg.prop('fill', "url('#blueGreenGradient')")
            // ),
            string.concat('cx="', current, '" cy="165" r="6" fill="url(#blueGreenGradient)"'),
            NULL
        );

        string memory shadowLine = svg.line(
            // string.concat(
            //     svg.prop('x1', '63'),
            //     svg.prop('y1', '165'),
            //     svg.prop('x2', '230'),
            //     svg.prop('y2', '165'),
            //     svg.prop('stroke', 'grey'),
            //     svg.prop('stroke-width', '4')
            // ),
            string.concat('x1="63" y1="165" x2="230" y2="165" stroke="grey" stroke-width="4"'),
            NULL
        );

        return svg.g(
            NULL,
            string.concat(
                startBar,
                shadowLine,
                progressLine,
                progress < 15 ? "" : animateLine(len),
                endBar,
                progress < 5 || progress > 95 ? "" : progressCircle
            )
        );
    }

    function animateLine(uint256 len) internal pure returns (string memory) {
        return svg.rect(
            // string.concat(
            //     svg.prop('x', '62'),
            //     svg.prop('y', '161'),
            //     svg.prop('width', '12'),
            //     svg.prop('height', '8'),
            //     svg.prop('fill', "url('#blueGreenGradient')"),
            //     svg.prop('rx', '4'),
            //     svg.prop('ry', '4')
            // ),
            string.concat(
                'x="62" y="161" width="12" height="8" fill="url(#blueGreenGradient)" rx="4" ry="4"'
            ),
            svg.el(
                "animate",
                // string.concat(
                //     svg.prop('attributeName', 'x'),
                //     svg.prop('values', string.concat('62;', LibString.toString(62 + len - 16), ';')),
                //     svg.prop('dur', string.concat(LibString.toString(((5 * len) / 168) + 1), 's')),
                //     svg.prop('repeatCount', 'indefinite')
                // ),
                string.concat(
                    'attributeName="x" values="62;',
                    LibString.toString(62 + len - 16),
                    ';" dur="',
                    LibString.toString(((5 * len) / 168) + 1),
                    's" repeatCount="indefinite"'
                ),
                NULL
            )
        );
    }

    function progressLabels(uint48 start_, uint48 expiry_) internal pure returns (string memory) {
        (string memory start, string memory expiry) = getTimeStrings(start_, expiry_);

        return string.concat(
            svg.text(
                // string.concat(
                //     svg.prop('x', '60'),
                //     svg.prop('y', '200'),
                //     svg.prop('font-size', '12'),
                //     TEXT_STYLE
                // ),
                string.concat('x="60" y="200" font-size="12" ', TEXT_STYLE),
                start
            ),
            svg.text(
                // string.concat(
                //     svg.prop('x', '230'),
                //     svg.prop('y', '200'),
                //     svg.prop('font-size', '12'),
                //     TEXT_STYLE
                // ),
                string.concat('x="230" y="200" font-size="12"', TEXT_STYLE),
                expiry
            )
        );
    }

    // ========== COLOR GRADIENTS ========== //

    function fullGradientStops() internal view returns (string memory) {
        // return string.concat(
        //     svg.gradientStop(
        //         2,
        //         colors.blue,
        //         NULL
        //     ),
        //     svg.gradientStop(
        //         10,
        //         colors.lightBlue,
        //         NULL
        //     ),
        //     svg.gradientStop(
        //         32,
        //         colors.green,
        //         NULL
        //     ),
        //     svg.gradientStop(
        //         49,
        //         colors.yellowGreen,
        //         NULL
        //     ),
        //     svg.gradientStop(
        //         52,
        //         colors.yellow,
        //         NULL
        //     ),
        //     svg.gradientStop(
        //         79,
        //         colors.orange,
        //         NULL
        //     ),
        //     svg.gradientStop(
        //         100,
        //         colors.red,
        //         NULL
        //     )
        // );
        return string.concat(
            '<stop offset="2" stop-color="',
            colors.blue,
            '"/>',
            '<stop offset="10" stop-color="',
            colors.lightBlue,
            '"/>',
            '<stop offset="32" stop-color="',
            colors.green,
            '"/>',
            '<stop offset="49" stop-color="',
            colors.yellowGreen,
            '"/>',
            '<stop offset="52" stop-color="',
            colors.yellow,
            '"/>',
            '<stop offset="79" stop-color="',
            colors.orange,
            '"/>',
            '<stop offset="100" stop-color="',
            colors.red,
            '"/>'
        );
    }

    function fullGradientReverseStops() internal view returns (string memory) {
        return string.concat(
            svg.gradientStop(2, colors.red, NULL),
            svg.gradientStop(21, colors.orange, NULL),
            svg.gradientStop(48, colors.yellow, NULL),
            svg.gradientStop(51, colors.yellowGreen, NULL),
            svg.gradientStop(68, colors.green, NULL),
            svg.gradientStop(90, colors.lightBlue, NULL),
            svg.gradientStop(100, colors.blue, NULL)
        );
        return string.concat(
            '<stop offset="2" stop-color="',
            colors.red,
            '"/>',
            '<stop offset="21" stop-color="',
            colors.orange,
            '"/>',
            '<stop offset="48" stop-color="',
            colors.yellow,
            '"/>',
            '<stop offset="51" stop-color="',
            colors.yellowGreen,
            '"/>',
            '<stop offset="68" stop-color="',
            colors.green,
            '"/>',
            '<stop offset="90" stop-color="',
            colors.lightBlue,
            '"/>',
            '<stop offset="100" stop-color="',
            colors.blue,
            '"/>'
        );
    }

    function fullGradient() internal view returns (string memory) {
        return
            svg.linearGradient(string.concat(svg.prop("id", "fullGradient")), fullGradientStops());
    }

    function fullGradient90() internal view returns (string memory) {
        return svg.linearGradient(
            string.concat(
                svg.prop("id", "fullGradient90"), svg.prop("gradientTransform", "rotate(90)")
            ),
            fullGradientStops()
        );
    }

    function fullGradientReverse90() internal view returns (string memory) {
        return svg.linearGradient(
            string.concat(
                svg.prop("id", "fullGradientReverse90"), svg.prop("gradientTransform", "rotate(90)")
            ),
            fullGradientReverseStops()
        );
    }

    function blueGreenGradient() internal view returns (string memory) {
        return svg.linearGradient(
            string.concat(
                svg.prop("id", "blueGreenGradient"), svg.prop("gradientUnits", "userSpaceOnUse")
            ),
            string.concat(
                '<stop offset="20" stop-color="',
                colors.blue,
                '"/>',
                '<stop offset="40" stop-color="',
                colors.lightBlue,
                '"/>',
                '<stop offset="60" stop-color="',
                colors.green,
                '"/>'
            )
        );
    }

    // function orangeRedGradient() internal view returns (string memory) {
    //     return svg.linearGradient(
    //         string.concat(
    //             svg.prop('id', 'orangeRedGradient'),
    //             svg.prop('gradientTransform', 'rotate(90)')
    //         ),
    //         string.concat(
    //             svg.gradientStop(
    //                 30,
    //                 colors.orange,
    //                 NULL
    //             ),
    //             svg.gradientStop(
    //                 90,
    //                 colors.red,
    //                 NULL
    //             )
    //         )
    //     );
    // }

    // ========== UTILITIES ========== //

    function getTimeStrings(
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
    // Used by hot-chain-svg during development. TODO: Remove for prod.

    function example() external view returns (string memory) {
        Info memory info = Info({
            baseAssetSymbol: "XYZ",
            tokenId: 123_456,
            start: 1_717_200_000, // 2024-06-01
            expiry: 1_725_148_800 // 2024-09-01
        });

        return render(info);
    }
}
