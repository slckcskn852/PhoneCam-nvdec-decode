#pragma once
#include <algorithm>
#include <cmath>
namespace phonecam {
// Start at 10 ms; grow quickly for measured jitter and recover gradually.
class LatencyController {
public:
    int update(double jitterMs, double lossFraction) {
        if (!std::isfinite(jitterMs) || !std::isfinite(lossFraction)) return delay_;
        const int desired = std::clamp(static_cast<int>(std::ceil(std::clamp(jitterMs, 0.0, 1000.0) * 2)) +
                                       (lossFraction > 0.01 ? 10 : 5), 5, 50);
        delay_ = desired > delay_ ? desired : std::max(desired, delay_ - 1);
        return delay_;
    }
    int delay() const { return delay_; }
    void reset() { delay_ = 10; }
private:
    int delay_ = 10;
};
}
