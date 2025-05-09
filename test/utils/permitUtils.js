const { ethers } = require("hardhat");
const { DAI_ADDRESS } = require("./getCoin");

// 获取签名信息
// 只有 DAI 和 USDC 支持签名交易，USDT 不支持
async function getSignMessage(token, token_abi, owner, spender, amount, deadline){    
    
    let signer = await ethers.getImpersonatedSigner(owner);
    let coinProvider = new ethers.Contract(token, token_abi, ethers.provider);
    //console.log(signer);
    let chainId = (await signer.provider.getNetwork()).chainId; 
    //const chainId = 1n; 
    const name = await coinProvider.name();
    const nonce = await coinProvider.nonces(owner);
    const version = await coinProvider.version();

    var sign;
    if(token == DAI_ADDRESS){
        chainId = 1n; 
        const allowed = amount ? true : false;
        console.log({name, version, chainId, verifyingContract: token });
        sign = ethers.Signature.from(
            await signer.signTypedData(
              {name, version, chainId, verifyingContract: token },
              {Permit: [
                    {name: "holder", type: "address"},
                    {name: "spender", type: "address"},
                    {name: "nonce", type: "uint256"},
                    {name: "expiry", type: "uint256"},
                    {name: "allowed", type: "bool"}
              ]},
              {holder: owner, spender, nonce, expiry: deadline, allowed}
            ));      
            console.log({holder: owner, spender, nonce, expiry: deadline, allowed});
    }else{
        sign = await _getCoinSign(name, version, chainId, token, owner, spender, amount, nonce, deadline)
    }
    
    return sign;
}

async function _getCoinSign(name, version, chainId, verifyingContract, owner, spender, value, nonce, deadline){    
    let signer = await ethers.getImpersonatedSigner(owner);

    console.log({name, version, chainId, verifyingContract });
    var sign = ethers.Signature.from(
        await signer.signTypedData(
            {name, version, chainId, verifyingContract },
            {Permit: [
                {name: "owner", type: "address"},
                {name: "spender", type: "address"},
                {name: "value", type: "uint256"},
                {name: "nonce", type: "uint256"},
                {name: "deadline", type: "uint256"}
            ]},
            {owner, spender, value, nonce, deadline}
        ));
    console.log({owner, spender, value, nonce, deadline});
    //console.log(sign);
    //console.log(sign.v);
    return sign;


}

async function getSignMessageByCoin(token, owner, spender, value, deadline){    
    
    let signer = await ethers.getImpersonatedSigner(owner);
    const chainId = (await signer.provider.getNetwork()).chainId; 
    const name = await token.name();
    const nonce = await token.nonces(owner);
    const version = await token.version();

    return await _getCoinSign(name, version, chainId, token.address, owner, spender, value, nonce, deadline)

}

// Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)
async function getSignMessageByNFT(token, owner, spender, tokenId, deadline){    
    
    let signer = await ethers.getImpersonatedSigner(owner);
    const chainId = (await signer.provider.getNetwork()).chainId; 
    const name = await token.name();
    const nonce = Number(await token.nonces(tokenId));
    const version = await token.version();
    //console.log({name, version, chainId, verifyingContract: token.address });
    var sign = ethers.Signature.from(
        await signer.signTypedData(
            {name, version, chainId, verifyingContract: token.address },
            {Permit: [
                {name: "spender", type: "address"},
                {name: "tokenId", type: "uint256"},
                {name: "nonce", type: "uint256"},
                {name: "deadline", type: "uint256"}
            ]},
            {spender, tokenId, nonce, deadline}
        ));
    //console.log({spender, tokenId, nonce, deadline});
    //console.log(sign);
    return sign;
}


// exports 
module.exports = {
    getSignMessage,
    getSignMessageByCoin,
    getSignMessageByNFT
};