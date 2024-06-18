/// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

import {svg, utils} from "src/lib/SVG.sol";

contract DerivativeCardDark {

    struct Info {
        string derivativeType;
        string baseAssetSymbol;
        string quoteAssetSymbol;
        string tokenId;
        string tokenAddress;
        string erc20Address;
        Property[] properties;
    }

    struct Property {
        string key;
        string stringValue;
        uint256 value;
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

    string internal constant STROKE = 'stroke="#000" stroke-miterlimit="10" stroke-width="4px" ';
    string internal constant TEXT_STYLE= 'font-family="\'Menlo\', monospace" fill="white"';

    Colors internal colors;

    constructor() {
        colors = Colors({
            blue: 'rgb(110, 148, 240)',
            lightBlue: 'rgb(118, 189, 242)',
            green: 'rgb(206, 244, 117)',
            yellowGreen: 'rgb(243, 244, 189)',
            yellow: 'rgb(243, 244, 189)',
            orange: 'rgb(246, 172, 84)',
            red: 'rgb(242, 103, 64)'
        });
    }

    function render(Info memory tokenInfo) internal view returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 290 500">',
            svg.el('defs', utils.NULL, string.concat(fullGradient(), fullGradient90(), fullGradientReverse90(), blueGreenGradient(), orangeRedGradient())),
            svg.rect(
                string.concat(
                    svg.prop('x', '0'),
                    svg.prop('y', '0'),
                    svg.prop('width', '290'),
                    svg.prop('height', '500'),
                    svg.prop('fill', 'rgb(30, 30, 30)'),
                    svg.prop('rx', '25'),
                    svg.prop('ry', '25')
                ),
                utils.NULL
            ),
            svg.rect(
                string.concat(
                    svg.prop('x', '8'),
                    svg.prop('y', '8'),
                    svg.prop('width', '274'),
                    svg.prop('height', '484'),
                    svg.prop('fill', 'none'),
                    svg.prop('stroke', "url('#fullGradientReverse90')"),
                    svg.prop('stroke-width', '2'),
                    svg.prop('rx', '20'),
                    svg.prop('ry', '20')
                ),
                utils.NULL
            ),
            svg.text(
                string.concat(
                    svg.prop('x', '145'),
                    svg.prop('y', '40'),
                    svg.prop('font-size', '20'),
                    svg.prop('text-anchor', 'middle'),
                    TEXT_STYLE
                ),
                tokenInfo.derivativeType
            ),
            svg.text(
                string.concat(
                    svg.prop('x', '145'),
                    svg.prop('y', '100'),
                    svg.prop('font-size', '56'),
                    svg.prop('text-anchor', 'middle'),
                    // svg.prop('font-family', 'Menlo, monospace'),
                    // svg.prop('fill', "url('#orangeRedGradient')")
                    TEXT_STYLE
                ),
                tokenInfo.baseAssetSymbol
            ),
            progressBar(tokenInfo.properties[0].value, tokenInfo.properties[1].value),
            svg.text(
                string.concat(
                    svg.prop('x', '60'),
                    svg.prop('y', '200'),
                    svg.prop('font-size', '12'),
                    svg.prop('text-anchor', 'middle'),
                    TEXT_STYLE
                ),
                tokenInfo.properties[0].stringValue
            ),
            svg.text(
                string.concat(
                    svg.prop('x', '230'),
                    svg.prop('y', '200'),
                    svg.prop('font-size', '12'),
                    svg.prop('text-anchor', 'middle'),
                    TEXT_STYLE
                ),
                tokenInfo.properties[1].stringValue
            ),
            logo(),
            svg.text(
                string.concat(
                    svg.prop('x', '145'),
                    svg.prop('y', '460'),
                    svg.prop('font-size', '10'),
                    svg.prop('text-anchor', 'middle'),
                    TEXT_STYLE
                ),
                tokenInfo.tokenAddress
            ),
            svg.text(
                string.concat(
                    svg.prop('x', '145'),
                    svg.prop('y', '480'),
                    svg.prop('font-size', '10'),
                    svg.prop('text-anchor', 'middle'),
                    TEXT_STYLE
                ),
                string.concat('ID: ', tokenInfo.tokenId)
            ),
            '</svg>'
        );
    }

    function logo() internal pure returns (string memory) {
        return string.concat(
            svg.rect(
                string.concat(
                    svg.prop('x', '143'),
                    svg.prop('y', '240'),
                    svg.prop('width', '6'),
                    svg.prop('height', '125'),
                    svg.prop('fill', "url('#fullGradientReverse90')")
                ),
                utils.NULL
            ),
            svg.rect(
                string.concat(
                    svg.prop('x', '79'),
                    svg.prop('y', '246'),
                    svg.prop('width', '6'),
                    svg.prop('height', '125'),
                    svg.prop('fill', "url('#fullGradient90')"),
                    svg.prop('transform', 'rotate(-60 145 250)')
                ),
                utils.NULL
            ),
            svg.rect(
                string.concat(
                    svg.prop('x', '206'),
                    svg.prop('y', '244'),
                    svg.prop('width', '6'),
                    svg.prop('height', '125'),
                    svg.prop('fill', "url('#fullGradient90')"),
                    svg.prop('transform', 'rotate(60 145 250)')
                ),
                utils.NULL
            )
        );
    }

    function fullGradientStops() internal view returns (string memory) {
        return string.concat(
            svg.gradientStop(
                2,
                colors.blue,
                utils.NULL
            ),
            svg.gradientStop(
                10,
                colors.lightBlue,
                utils.NULL
            ),
            svg.gradientStop(
                32,
                colors.green,
                utils.NULL
            ),
            svg.gradientStop(
                49,
                colors.yellowGreen,
                utils.NULL
            ),
            svg.gradientStop(
                52,
                colors.yellow,
                utils.NULL
            ),
            svg.gradientStop(
                79,
                colors.orange,
                utils.NULL
            ),
            svg.gradientStop(
                100,
                colors.red,
                utils.NULL
            )
        );
    }

    function fullGradientReverseStops() internal view returns (string memory) {
        return string.concat(
            svg.gradientStop(
                2,
                colors.red,
                utils.NULL
            ),
            svg.gradientStop(
                21,
                colors.orange,
                utils.NULL
            ),
            svg.gradientStop(
                48,
                colors.yellow,
                utils.NULL
            ),
            svg.gradientStop(
                51,
                colors.yellowGreen,
                utils.NULL
            ),
            svg.gradientStop(
                68,
                colors.green,
                utils.NULL
            ),
            svg.gradientStop(
                90,
                colors.lightBlue,
                utils.NULL
            ),
            svg.gradientStop(
                100,
                colors.blue,
                utils.NULL
            )
        );
    }

    function fullGradient() internal view returns (string memory) {
        return svg.linearGradient(
            string.concat(
                svg.prop('id', 'fullGradient')
            ),
            fullGradientStops()
        );
    }

    function fullGradient90() internal view returns (string memory) {
        return svg.linearGradient(
            string.concat(
                svg.prop('id', 'fullGradient90'),
                svg.prop('gradientTransform', 'rotate(90)')
            ),
            fullGradientStops()
        );
    }

    function fullGradientReverse90() internal view returns (string memory) {
        return svg.linearGradient(
            string.concat(
                svg.prop('id', 'fullGradientReverse90'),
                svg.prop('gradientTransform', 'rotate(90)')
            ),
            fullGradientReverseStops()
        );
    }

    function blueGreenGradient() internal view returns (string memory) {
        return svg.linearGradient(
            string.concat(
                svg.prop('id', 'blueGreenGradient'),
                svg.prop('gradientUnits', 'userSpaceOnUse')
            ),
            string.concat(
                svg.gradientStop(
                    20,
                    colors.blue,
                    utils.NULL
                ),
                svg.gradientStop(
                    40,
                    colors.lightBlue,
                    utils.NULL
                ),
                svg.gradientStop(
                    60,
                    colors.green,
                    utils.NULL
                )
            )
        );
    }

    function orangeRedGradient() internal view returns (string memory) {
        return svg.linearGradient(
            string.concat(
                svg.prop('id', 'orangeRedGradient'),
                svg.prop('gradientTransform', 'rotate(90)')
            ),
            string.concat(
                svg.gradientStop(
                    30,
                    colors.orange,
                    utils.NULL
                ),
                svg.gradientStop(
                    90,
                    colors.red,
                    utils.NULL
                )
            )
        );
    }

    function progressBar(uint256 start, uint256 end) internal view returns (string memory) {
        uint256 currentTime = 1717200000 + 70 * 86400; // block.timestamp;

        bool started = start <= currentTime;
        
        uint256 progress = started ? (currentTime - start) * 100 / (end - start) : 0;
        // progress can be at most 100
        progress = progress > 100 ? 100 : progress;

        uint256 len = (168 * progress) / 100;

        string memory startBar = svg.line(
            string.concat(
                svg.prop('x1', '60'),
                svg.prop('y1', '155'),
                svg.prop('x2', '60'),
                svg.prop('y2', '175'),
                svg.prop('stroke', started ? colors.blue : 'grey'),
                svg.prop('stroke-width', '6')
            ),
            utils.NULL
        );

        string memory endBar = svg.line(
            string.concat(
                svg.prop('x1', '230'),
                svg.prop('y1', '155'),
                svg.prop('x2', '230'),
                svg.prop('y2', '175'),
                svg.prop('stroke', progress == 100 ? colors.green : 'grey'),
                svg.prop('stroke-width', '6')
            ),
            utils.NULL
        );


        string memory progressLine = svg.line(
            string.concat(
                svg.prop('x1', '62'),
                svg.prop('y1', '165'),
                svg.prop('x2', utils.uint2str(62 + len)),
                svg.prop('y2', '165'),
                svg.prop('stroke', "url('#blueGreenGradient')"),
                svg.prop('stroke-width', '6')
            ),
            utils.NULL
        );

        string memory animateLine = svg.rect(
            string.concat(
                svg.prop('x', '62'),
                svg.prop('y', '161'),
                svg.prop('width', '16'),
                svg.prop('height', '8'),
                svg.prop('fill', "url('#blueGreenGradient')"),
                svg.prop('rx', '4'),
                svg.prop('ry', '4')
            ),
            svg.el('animate', 
                string.concat(
                    svg.prop('attributeName', 'x'),
                    svg.prop('values', string.concat('62;', utils.uint2str(62 + len - 16), ';')),
                    svg.prop('dur', '3s'),
                    svg.prop('repeatCount', 'indefinite')
                ),
                utils.NULL
            )
        );

        string memory shadowLine = svg.line(
            string.concat(
                svg.prop('x1', '63'),
                svg.prop('y1', '165'),
                svg.prop('x2', '230'),
                svg.prop('y2', '165'),
                svg.prop('stroke', 'grey'),
                svg.prop('stroke-width', '4')
            ),
            utils.NULL
        );

        string memory progressCircle = svg.circle(
            string.concat(
                svg.prop('cx', utils.uint2str(62 + len)),
                svg.prop('cy', '165'),
                svg.prop('r', '6'),
                svg.prop('fill', "url('#blueGreenGradient')")
            ),
            utils.NULL
        );

        return svg.g(
            utils.NULL,
            string.concat(
                startBar,
                shadowLine,
                progressLine,
                progress < 5 ? '' : animateLine,
                endBar,
                progress < 5 || progress > 95 ? '' : progressCircle
            )
        );
    }

    function example() external view returns (string memory) {
        Property[] memory properties = new Property[](2);
        properties[0] = Property({key: "Vesting Start", stringValue: "2024-06-01", value: 1717200000});
        properties[1] = Property({key: "Vesting End", stringValue: "2024-09-01", value: 1725148800});


        Info memory info = Info({
            derivativeType: "Linear Vesting",
            baseAssetSymbol: "XYZ",
            quoteAssetSymbol: "",
            tokenId: "123456",
            tokenAddress: "0x1234567890123456789012345678901234567890",
            erc20Address: "0xfedcba0987654321fedcba0987654321fedcba09",
            properties: properties
        });

        return render(info);
    }

}