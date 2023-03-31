import { ethers } from "hardhat";
import { expect } from "chai";

// JWKS values are base64url encoded
// For a given key, e.g. sguIKIvlEVBsEGk77iV2yNQxpY_Qkiy3yuMfY4wpmnPlevlDKASu6uP_CGubzThiBHlChYDDNvYfOitWXDwpxbJ_MqmajA-dDbrI5LdggyJpSoWPKThPJ1CKRhRiRXJjXGi6Gg6TfbYRwu0ziyDgZZ125NszuNOUO1pc1qGun4SPifzY7OY6BtADZDqTWHFTfm_yhgBgyElE-r4d-ZqPe9tYYqCnAvILBuZbPYt3UC3fAr9JltdUO54vxKblo2z2fd-H9zBn9jRZOBkuVVB8QSV5sre-H23CTBABSpZpe0SrJpXgG9AuV4Da7FRHBC9A-oLYLe-UF5_5c6_cd7c_KQ
// The oracle will call our contract with the key encoded as base64url. This key is stored as a hex string in variable n below.
// Decoding this key in solidity should result in the expectedValue

describe("Base64DecodeTest", function () {

    const n = '0x736775494b49766c4556427345476b3737695632794e517870595f516b69793379754d66593477706d6e506c65766c444b4153753675505f434775627a54686942486c43685944444e7659664f6974575844777078624a5f4d716d616a412d6444627249354c646767794a70536f57504b5468504a31434b5268526952584a6a5847693647673654666259527775307a697944675a5a3132354e737a754e4f554f317063317147756e34535069667a59374f5936427441445a44715457484654666d5f796867426779456c452d7234642d5a7150653974595971436e4176494c42755a6250597433554333664172394a6c7464554f353476784b626c6f327a3266642d48397a426e396a525a4f426b7556564238515356357372652d483233435442414253705a70653053724a705867473941755634446137465248424339412d6f4c594c652d5546355f3563365f636437635f4b51';
    const expectedResult = '0xb20b88288be511506c10693bee2576c8d431a58fd0922cb7cae31f638c299a73e57af9432804aeeae3ff086b9bcd38620479428580c336f61f3a2b565c3c29c5b27f32a99a8c0f9d0dbac8e4b7608322694a858f29384f27508a4614624572635c68ba1a0e937db611c2ed338b20e0659d76e4db33b8d3943b5a5cd6a1ae9f848f89fcd8ece63a06d003643a935871537e6ff2860060c84944fabe1df99a8f7bdb5862a0a702f20b06e65b3d8b77502ddf02bf4996d7543b9e2fc4a6e5a36cf67ddf87f73067f6345938192e55507c412579b2b7be1f6dc24c10014a96697b44ab2695e01bd02e5780daec5447042f40fa82d82def94179ff973afdc77b73f29';

    it('decodes', async function () {
        const Base64DecodeTest = await ethers.getContractFactory("Base64DecodeTest");
        const b64 = await Base64DecodeTest.deploy();
        const result = await b64.getN(n);
        expect(result).to.equal(expectedResult);
    });

});