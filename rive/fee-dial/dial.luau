-- dial.luau - drag anywhere to set the sale; every figure recomputes.
--
-- The fee is max(5% of the sale, 50c), which is what Event::Plan actually
-- charges (MINIMUM_FEE_CENTS, app/models/event/plan.rb). It is computed here in
-- integer cents for the same reason the app does it in cents: 0.05 * a float
-- dollar amount lands on 19.999999 often enough to matter, and a rounding error
-- in a number a teenager is deciding their price from is not a cosmetic bug.
--
-- The script writes view model properties and never touches the scene graph.
-- Numbers cannot drive a text run in Rive, so the money strings are formatted
-- here and bound to the runs as strings.
--
-- The slider is logarithmic on purpose. On a linear $5-$2000 track the entire
-- region where the 50c floor actually bites - under $10 - is the first quarter
-- of one percent of the travel, so the floor would be invisible. Here it has
-- real estate, and you can watch the effective rate climb as the sale shrinks.

local X0 = 150.0 -- track left, artboard units
local W = 600.0 -- track length
local LO = 5.0 -- cheapest sale on the dial
local SPAN = 400.0 -- LO * SPAN = the dearest, so $5 .. $2000

type Dial = {
    size: Vector,
    knobX: Property<number>?,
    fillW: Property<number>?,
    payoutW: Property<number>?,
    feeW: Property<number>?,
    amount: Property<string>?,
    payout: Property<string>?,
    fee: Property<string>?,
    rate: Property<string>?,
    x: number,
    targetX: number,
    down: boolean,
    last: number,
}

-- 1234567 -> "1,234,567"
local function commas(whole: string): string
    local out = whole
    while true do
        local next, n = string.gsub(out, '^(%-?%d+)(%d%d%d)', '%1,%2')
        out = next
        if n == 0 then
            break
        end
    end
    return out
end

-- cents -> "$1,234.56"
local function money(cents: number): string
    local c = math.floor(cents + 0.5)
    local whole = math.floor(c / 100)
    local frac = c - whole * 100
    return '$' .. commas(tostring(whole)) .. string.format('.%02d', frac)
end

function init(self: Dial, context: Context): boolean
    -- init runs twice and the view model is absent the first time.
    local vm = context:viewModel()
    if vm == nil then
        return true
    end
    self.knobX = vm:getNumber('knobX')
    self.fillW = vm:getNumber('fillW')
    self.payoutW = vm:getNumber('payoutW')
    self.feeW = vm:getNumber('feeW')
    self.amount = vm:getString('amount')
    self.payout = vm:getString('payout')
    self.fee = vm:getString('fee')
    self.rate = vm:getString('rate')
    return true
end

function resize(self: Dial, size: Vector)
    self.size = size
end

-- event:hit() on every event of the gesture, not just the press: without it on
-- the moves, an enclosing hit target claims the drag one frame in.
function pointerDown(self: Dial, event: PointerEvent)
    self.down = true
    self.targetX = event.position.x
    event:hit()
end

function pointerMove(self: Dial, event: PointerEvent)
    if self.down then
        self.targetX = event.position.x
        event:hit()
    end
end

function pointerUp(self: Dial, event: PointerEvent)
    if self.down then
        self.down = false
        event:hit()
    end
end

function pointerExit(self: Dial, event: PointerEvent)
    self.down = false
end

function advance(self: Dial, seconds: number): boolean
    -- Frame-rate independent follow, so the knob eases instead of snapping.
    local k = 1 - math.exp(-16 * seconds)
    self.x += (self.targetX - self.x) * k

    local t = math.clamp((self.x - X0) / W, 0, 1)
    local dollars = math.floor(LO * math.pow(SPAN, t) + 0.5)
    if dollars < LO then
        dollars = LO
    end

    local cents = dollars * 100
    local feeCents = math.max(math.floor(cents * 0.05 + 0.5), 50)
    local payCents = cents - feeCents

    if self.knobX ~= nil then
        self.knobX.value = X0 + t * W
    end
    if self.fillW ~= nil then
        self.fillW.value = t * W
    end

    -- The bar is the split, to scale. A 2px gap on each side of the seam keeps
    -- the two segments legible when the fee slice gets thin.
    local payFrac = payCents / cents
    if self.payoutW ~= nil then
        self.payoutW.value = math.max(payFrac * W - 2, 0)
    end
    if self.feeW ~= nil then
        self.feeW.value = math.max((1 - payFrac) * W - 2, 3)
    end

    -- Strings only change when the rounded dollar value does; rewriting them
    -- every frame would re-shape text 60 times a second for nothing.
    if dollars ~= self.last then
        self.last = dollars
        if self.amount ~= nil then
            self.amount.value = '$' .. commas(tostring(dollars))
        end
        if self.payout ~= nil then
            self.payout.value = money(payCents)
        end
        if self.fee ~= nil then
            self.fee.value = '−' .. money(feeCents)
        end
        if self.rate ~= nil then
            local pct = feeCents / cents * 100
            self.rate.value = string.format("That's %.1f%% of this sale", pct)
        end
    end
    return true
end

return function(context: Context): Layout<Dial>
    return {
        size = Vector.xy(0, 0),
        knobX = nil,
        fillW = nil,
        payoutW = nil,
        feeW = nil,
        amount = nil,
        payout = nil,
        fee = nil,
        rate = nil,
        -- $400 at rest, the same worked example the rest of the set uses.
        x = X0 + W * (math.log(400 / LO) / math.log(SPAN)),
        targetX = X0 + W * (math.log(400 / LO) / math.log(SPAN)),
        down = false,
        last = -1,
        init = init,
        resize = resize,
        advance = advance,
        pointerDown = pointerDown,
        pointerMove = pointerMove,
        pointerUp = pointerUp,
        pointerExit = pointerExit,
    }
end
