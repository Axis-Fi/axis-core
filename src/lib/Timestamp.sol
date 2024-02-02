/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

library Timestamp {
    function toPaddedString(uint48 timestamp)
        public
        pure
        returns (string memory, string memory, string memory)
    {
        // Convert a number of days into a human-readable date, courtesy of BokkyPooBah.
        // Source: https://github.com/bokkypoobah/BokkyPooBahsDateTimeLibrary/blob/master/contracts/BokkyPooBahsDateTimeLibrary.sol

        uint256 year;
        uint256 month;
        uint256 day;
        {
            int256 __days = int256(int48(timestamp) / 1 days);

            int256 num1 = __days + 68_569 + 2_440_588; // 2440588 = OFFSET19700101
            int256 num2 = (4 * num1) / 146_097;
            num1 = num1 - (146_097 * num2 + 3) / 4;
            int256 _year = (4000 * (num1 + 1)) / 1_461_001;
            num1 = num1 - (1461 * _year) / 4 + 31;
            int256 _month = (80 * num1) / 2447;
            int256 _day = num1 - (2447 * _month) / 80;
            num1 = _month / 11;
            _month = _month + 2 - 12 * num1;
            _year = 100 * (num2 - 49) + _year + num1;

            year = uint256(_year);
            month = uint256(_month);
            day = uint256(_day);
        }

        string memory yearStr = _uint2str(year % 10_000);
        string memory monthStr =
            month < 10 ? string(abi.encodePacked("0", _uint2str(month))) : _uint2str(month);
        string memory dayStr =
            day < 10 ? string(abi.encodePacked("0", _uint2str(day))) : _uint2str(day);

        return (yearStr, monthStr, dayStr);
    }

    // Some fancy math to convert a uint into a string, courtesy of Provable Things.
    // Updated to work with solc 0.8.0.
    // https://github.com/provable-things/ethereum-api/blob/master/provableAPI_0.6.sol
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
