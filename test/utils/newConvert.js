

// 1$ -> 1 GLDC 每注1个份额
const daoCoinPrice = BigInt(1 * (10 ** 18));
// 0.0005 ETH -> 1 GLDC 每注2个份额
const daoCoinPriceEth = BigInt(5 * (10 ** 14));

function getDaoShares(assets, isEth) {
    let price = isEth? daoCoinPriceEth : daoCoinPrice;
    return BigInt(assets) * 10n ** 18n / price;
}

module.exports = {
    getDaoShares,
}
