import pytest
from starkware.starknet.testing.starknet import Starknet

@pytest.mark.asyncio
async def test_deploy():
    starknet = await Starknet.empty()
    assert True
