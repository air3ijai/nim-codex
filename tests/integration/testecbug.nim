from pkg/libp2p import Cid, init

# import pkg/codex/manifest
import pkg/codex/manifest/coders
import pkg/codex/manifest/manifest

import ../examples
import ./marketplacesuite
import ./nodeconfigs
import ./hardhatconfig

export coders # make Manifest.decode symbol available to codex/manifest

marketplacesuite "EC bug":

  test "should be able to create storage request and download dataset",
    NodeConfigs(
      # Uncomment to start Hardhat automatically, typically so logs can be
      # inspected locally
      hardhat: HardhatConfig().withLogFile().some,

      clients:
        CodexConfigs.init(nodes=1)
          # .debug() # uncomment to enable console log output.debug()
          .withLogFile() # uncomment to output log file to tests/integration/logs/<start_datetime> <suite_name>/<test_name>/<node_role>_<node_idx>.log
          .withLogTopics("node", "erasure", "marketplace", "storestream")
          .some,

      providers:
        CodexConfigs.none,
  ):
    let reward = 400.u256
    let duration = 10.periods
    let collateral = 200.u256
    let expiry = 5.periods
    let data = await RandomChunker.example(blocks=8)
    let client = clients()[0]
    let clientApi = client.client

    let cid = clientApi.upload(data).get

    var requestId = none RequestId
    proc onStorageRequested(event: StorageRequested) {.raises:[].} =
      echo "storage requested event"
      requestId = event.requestId.some

    let subscription = await marketplace.subscribe(StorageRequested, onStorageRequested)

    # client requests storage but requires multiple slots to host the content
    let id = await clientApi.requestStorage(
      cid,
      duration=duration,
      reward=reward,
      expiry=expiry,
      collateral=collateral,
      nodes=3,
      tolerance=1
    )

    check eventually(requestId.isSome, timeout=expiry.int * 1000)

    let request = await marketplace.getRequest(requestId.get)
    let cidFromRequest = Cid.init(request.content.cid).get()
    let downloaded = await clientApi.downloadBytes(cidFromRequest, local = true)
    check downloaded.isOk
    # let manifest = Manifest.new(downloaded.get)
    # echo "manifest: ", manifest
    echo "orig data length: ", data.len
    echo "download length: ", downloaded.get.len

    check downloaded.get.toHex == data.toHex

    await subscription.unsubscribe()