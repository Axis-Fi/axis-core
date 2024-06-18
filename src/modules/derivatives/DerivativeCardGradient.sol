/// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

import {svg, utils} from "src/lib/SVG.sol";

contract DerivativeCardDark {

    struct Info {
        string derivativeType;
        string baseAssetSymbol;
        string quoteAssetSymbol;
        Property[] properties;
    }

    struct Property {
        string key;
        string value;
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
    string internal constant TEXT_STYLE= 'font-family="\'Menlo\', monospace" fill="black"';

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
            svg.el('defs', utils.NULL, string.concat(fullGradient(), fullVertGradient(), blueGreenGradient(), orangeRedGradient())),
            svg.rect(
                string.concat(
                    svg.prop('x', '5'),
                    svg.prop('y', '5'),
                    svg.prop('width', '280'),
                    svg.prop('height', '490'),
                    svg.prop('fill', "url('#orangeRedGradient')"),
                    svg.prop('stroke', 'black'),
                    svg.prop('rx', '10'),
                    svg.prop('ry', '10')
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
                    TEXT_STYLE
                ),
                tokenInfo.baseAssetSymbol
            ),
            progressBar(80),
            svg.g(
                string.concat(
                    svg.prop('transform', 'translate(96, 200) scale(0.1)')
                ),
                logo()
            ),
            svg.text(
                string.concat(
                    svg.prop('x', '20'),
                    svg.prop('y', '350'),
                    svg.prop('font-size', '16'),
                    svg.prop('text-anchor', 'left'),
                    TEXT_STYLE
                ),
                string.concat(
                    tokenInfo.properties[0].key,
                    ': ',
                    tokenInfo.properties[0].value
                )
            ),
            svg.text(
                string.concat(
                    svg.prop('x', '20'),
                    svg.prop('y', '380'),
                    svg.prop('font-size', '16'),
                    svg.prop('text-anchor', 'left'),
                    TEXT_STYLE
                ),
                string.concat(
                    tokenInfo.properties[1].key,
                    ': ',
                    tokenInfo.properties[1].value
                )
            ),
            // svg.g(
            //     string.concat(
            //         svg.prop('transform', 'translate(80, 430) scale(0.05)')
            //     ),
            //     wordmark()
            // ),
            '</svg>'
        );
    }

    function logo() internal pure returns (string memory) {
        return svg.path(
            string.concat(
                svg.prop('fill' , 'white'),
                STROKE,
                svg.prop('d', 'M0.34668 818.666L20.3467 852.666L474.347 590.666V838.666H513.347V590.666L966.347 852.666L986.347 818.666L532.347 556.666L746.347 433.666L726.347 399.666L513.347 522.666L514.347 0.665527H474.347V522.666L260.347 399.666L240.347 433.666L454.347 556.666L0.34668 818.666Z')
            ),
            utils.NULL
        );
    }

    function wordmark() internal pure returns (string memory) {
        return svg.path(
            string.concat(
                svg.prop('fill' , "url('#fullGradient')"),
                STROKE,
                svg.prop('d', 'M2078.65 610.666H2118.65C2118.65 720.666 2205.65 799.666 2327.65 799.666C2439.65 799.666 2528.65 738.666 2528.65 629.666C2528.65 526.666 2460.65 465.666 2318.65 428.666C2167.65 397.666 2090.65 318.666 2090.65 201.666C2090.65 84.6656 2204.65 -2.33439 2323.65 0.665612C2450.65 -2.33439 2559.65 90.6656 2559.65 223.666H2521.65C2521.65 112.666 2432.65 40.6656 2323.65 40.6656C2223.65 40.6656 2130.65 110.666 2130.65 201.666C2130.65 300.666 2200.65 360.666 2331.65 394.666C2492.65 431.666 2569.65 505.666 2569.65 624.666C2569.65 743.666 2461.65 839.666 2323.65 839.666C2185.65 839.666 2078.65 742.666 2078.65 610.666ZM1926.65 820.666V20.6656H1966.65V820.666H1926.65ZM1005.65 801.666L1035.65 831.666L1416.65 450.666L1797.65 830.666L1826.65 800.666L1445.65 419.666L1826.65 40.6656L1796.65 10.6656L1415.65 391.666L1034.65 11.6656L1005.65 41.6656L1386.65 419.666L1005.65 801.666ZM45.6533 419.666C45.6533 627.666 212.653 794.666 419.653 794.666C611.653 794.666 793.653 648.666 793.653 419.666C793.653 190.666 611.653 45.6656 419.653 45.6656C212.653 45.6656 45.6533 213.666 45.6533 419.666ZM0.65332 419.666C0.65332 188.666 188.653 0.665612 419.653 0.665612C582.653 0.665612 761.653 103.666 817.653 299.666L869.653 20.6656H910.653L833.653 419.666L910.653 820.666H869.653L817.653 540.666C761.653 736.666 582.653 839.666 419.653 839.666C188.653 839.666 0.65332 651.666 0.65332 419.666Z')
            ),
            utils.NULL
        );
    }

    function fullGradient() internal view returns (string memory) {
        return svg.linearGradient(
            string.concat(
                svg.prop('id', 'fullGradient')
            ),
            string.concat(
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
            )
        );
    }

    function fullVertGradient() internal view returns (string memory) {
        return svg.linearGradient(
            string.concat(
                svg.prop('id', 'fullVertGradient'),
                svg.prop('gradientTransform', 'rotate(90)')
            ),
            string.concat(
                svg.gradientStop(
                    8,
                    colors.blue,
                    utils.NULL
                ),
                svg.gradientStop(
                    20,
                    colors.lightBlue,
                    utils.NULL
                ),
                svg.gradientStop(
                    42,
                    colors.green,
                    utils.NULL
                ),
                svg.gradientStop(
                    59,
                    colors.yellowGreen,
                    utils.NULL
                ),
                svg.gradientStop(
                    65,
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
            )
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
                svg.prop('gradientTransform', 'rotate(60)')
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

    function progressBar(uint256 _progress) internal view returns (string memory) {

        uint256 len = 168 * _progress / 100;

        string memory startBar = svg.line(
            string.concat(
                svg.prop('x1', '60'),
                svg.prop('y1', '135'),
                svg.prop('x2', '60'),
                svg.prop('y2', '155'),
                svg.prop('stroke', colors.blue),
                svg.prop('stroke-width', '6')
            ),
            utils.NULL
        );

        string memory endBarColor = _progress == 100 ? colors.green : 'grey';

        string memory endBar = svg.line(
            string.concat(
                svg.prop('x1', '230'),
                svg.prop('y1', '135'),
                svg.prop('x2', '230'),
                svg.prop('y2', '155'),
                svg.prop('stroke', endBarColor),
                svg.prop('stroke-width', '6')
            ),
            utils.NULL
        );


        string memory progressLine = svg.line(
            string.concat(
                svg.prop('x1', '63'),
                svg.prop('y1', '145'),
                svg.prop('x2', utils.uint2str(62 + len)),
                svg.prop('y2', '145'),
                svg.prop('stroke', "url('#blueGreenGradient')"),
                svg.prop('stroke-width', '6')
            ),
            utils.NULL
        );

        string memory shadowLine = svg.line(
            string.concat(
                svg.prop('x1', '63'),
                svg.prop('y1', '145'),
                svg.prop('x2', '230'),
                svg.prop('y2', '145'),
                svg.prop('stroke', 'grey'),
                svg.prop('stroke-width', '4')
            ),
            utils.NULL
        );

        return svg.g(
            utils.NULL,
            string.concat(
                startBar,
                shadowLine,
                progressLine,
                endBar
            )
        );
    }

    function example() external view returns (string memory) {
        Property[] memory properties = new Property[](2);
        properties[0] = Property({key: "Vesting Start", value: "2024-07-01"});
        properties[1] = Property({key: "Vesting End", value: "2024-09-01"});


        Info memory info = Info({
            derivativeType: "Linear Vesting",
            baseAssetSymbol: "XYZ",
            quoteAssetSymbol: "",
            properties: properties
        });

        return render(info);
    }

}