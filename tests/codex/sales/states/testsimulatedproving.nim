import pkg/asynctest
import pkg/chronos
import pkg/questionable
import pkg/codex/contracts/requests
import pkg/codex/sales/states/provingsimulated
import pkg/codex/sales/states/proving
import pkg/codex/sales/states/cancelled
import pkg/codex/sales/states/failed
import pkg/codex/sales/states/payout
import pkg/codex/sales/salesagent
import pkg/codex/sales/salescontext
import ../../examples
import ../../helpers
import ../../helpers/mockmarket
import ../../helpers/mockclock

asyncchecksuite "sales state 'simulated-proving'":

  let slot = Slot.example
  let request = slot.request
  let proof = exampleProof()
  let failEveryNProofs = 3
  let totalProofs = 6

  var market: MockMarket
  var clock: MockClock
  var agent: SalesAgent
  var state: SaleProvingSimulated

  var proofSubmitted: Future[void] = newFuture[void]("proofSubmitted")
  var submitted: seq[seq[byte]]
  var subscription: Subscription

  setup:
    clock = MockClock.new()

    proc onProofSubmission(id: SlotId, proof: seq[byte]) =
      submitted.add(proof)
      proofSubmitted.complete()
      proofSubmitted = newFuture[void]("proofSubmitted")

    market = MockMarket.new()
    market.slotState[slot.id] = SlotState.Filled
    market.setProofRequired(slot.id, true)
    subscription = await market.subscribeProofSubmission(onProofSubmission)

    let onProve = proc (slot: Slot): Future[seq[byte]] {.async.} =
                        return proof
    let context = SalesContext(market: market, clock: clock, onProve: onProve.some)
    agent = newSalesAgent(context,
                          request.id,
                          slot.slotIndex,
                          request.some)
    state = SaleProvingSimulated.new()
    state.failEveryNProofs = failEveryNProofs

  teardown:
    await subscription.unsubscribe()

  proc advanceToNextPeriod(market: Market) {.async.} =
    let periodicity = await market.periodicity()
    clock.advance(periodicity.seconds.truncate(int64))

  proc waitForProvingRounds(market: Market, rounds: int) {.async.} =
    var rnds = rounds - 1 # proof round runs prior to advancing
    while rnds > 0:
      await market.advanceToNextPeriod()
      await proofSubmitted
      rnds -= 1

  test "switches to cancelled state when request expires":
    let next = state.onCancelled(request)
    check !next of SaleCancelled

  test "switches to failed state when request fails":
    let next = state.onFailed(request)
    check !next of SaleFailed

  test "submits invalid proof every 3 proofs":
    let future = state.run(agent)

    await market.waitForProvingRounds(totalProofs)
    check submitted == @[proof, proof, @[], proof, proof, @[]]

    await future.cancelAndWait()

  test "switches to payout state when request is finished":
    market.slotState[slot.id] = SlotState.Filled

    let future = state.run(agent)

    market.slotState[slot.id] = SlotState.Finished
    await market.advanceToNextPeriod()

    check eventuallyCheck future.finished
    check !(future.read()) of SalePayout