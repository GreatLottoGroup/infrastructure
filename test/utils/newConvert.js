

// 1$ -> 1 GLDC 每注1个份额
const daoCoinPrice = BigInt(1 * (10 ** 18));

function getDaoShares(assets) {
    return BigInt(assets) * 10n ** 18n / daoCoinPrice;
}

module.exports = {
    getDaoShares,
}
