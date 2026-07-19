#include "control_parser.h"
#include <sstream>
#include <stdexcept>
#include <cmath>
#include <functional>

namespace phonecam {

JsonValue JsonParser::parse(const std::string& json) {
    size_t index = 0;
    auto skipWhitespace = [](const std::string& js, size_t& idx) {
        while (idx < js.size() && (js[idx] == ' ' || js[idx] == '\t' || js[idx] == '\n' || js[idx] == '\r')) {
            idx++;
        }
    };

    auto parseString = [](const std::string& js, size_t& idx) -> JsonValue {
        JsonValue val;
        val.type = JsonValue::Type::String;
        idx++; // skip '"'
        std::string s;
        while (idx < js.size()) {
            char c = js[idx];
            if (c == '"') {
                idx++;
                break;
            }
            if (c == '\\' && idx + 1 < js.size()) {
                idx++;
                c = js[idx];
                if (c == 'n') s += '\n';
                else if (c == 'r') s += '\r';
                else if (c == 't') s += '\t';
                else s += c;
            } else {
                s += c;
            }
            idx++;
        }
        val.strVal = s;
        return val;
    };

    auto parseNumber = [](const std::string& js, size_t& idx) -> JsonValue {
        JsonValue val;
        val.type = JsonValue::Type::Number;
        size_t start = idx;
        if (js[idx] == '-') idx++;
        while (idx < js.size() && ((js[idx] >= '0' && js[idx] <= '9') || js[idx] == '.' || js[idx] == 'e' || js[idx] == 'E' || js[idx] == '+' || js[idx] == '-')) {
            idx++;
        }
        std::string s = js.substr(start, idx - start);
        try {
            val.numVal = std::stod(s);
        } catch (...) {
            val.numVal = 0.0;
        }
        return val;
    };

    std::function<JsonValue(const std::string&, size_t&)> parseValue = [&](const std::string& js, size_t& idx) -> JsonValue {
        skipWhitespace(js, idx);
        if (idx >= js.size()) return {};

        char c = js[idx];
        if (c == '{') {
            JsonValue val;
            val.type = JsonValue::Type::Object;
            idx++; // skip '{'
            while (idx < js.size()) {
                skipWhitespace(js, idx);
                if (idx >= js.size()) break;
                if (js[idx] == '}') {
                    idx++;
                    break;
                }
                if (js[idx] != '"') break;
                JsonValue keyVal = parseString(js, idx);
                skipWhitespace(js, idx);
                if (idx >= js.size() || js[idx] != ':') break;
                idx++; // skip ':'
                JsonValue memberVal = parseValue(js, idx);
                val.objVal[keyVal.strVal] = memberVal;

                skipWhitespace(js, idx);
                if (idx >= js.size()) break;
                if (js[idx] == ',') {
                    idx++;
                } else if (js[idx] == '}') {
                    idx++;
                    break;
                } else {
                    break;
                }
            }
            return val;
        } else if (c == '[') {
            JsonValue val;
            val.type = JsonValue::Type::Array;
            idx++; // skip '['
            while (idx < js.size()) {
                skipWhitespace(js, idx);
                if (idx >= js.size()) break;
                if (js[idx] == ']') {
                    idx++;
                    break;
                }
                JsonValue item = parseValue(js, idx);
                val.arrVal.push_back(item);

                skipWhitespace(js, idx);
                if (idx >= js.size()) break;
                if (js[idx] == ',') {
                    idx++;
                } else if (js[idx] == ']') {
                    idx++;
                    break;
                } else {
                    break;
                }
            }
            return val;
        } else if (c == '"') {
            return parseString(js, idx);
        } else if (c == '-' || (c >= '0' && c <= '9')) {
            return parseNumber(js, idx);
        } else if (js.compare(idx, 4, "true") == 0) {
            idx += 4;
            JsonValue val;
            val.type = JsonValue::Type::Bool;
            val.boolVal = true;
            return val;
        } else if (js.compare(idx, 5, "false") == 0) {
            idx += 5;
            JsonValue val;
            val.type = JsonValue::Type::Bool;
            val.boolVal = false;
            return val;
        } else if (js.compare(idx, 4, "null") == 0) {
            idx += 4;
            return {};
        }
        return {};
    };

    return parseValue(json, index);
}

ControlMessage parseControlMessage(const std::string& jsonStr) {
    JsonValue root = JsonParser::parse(jsonStr);
    ControlMessage msg;
    msg.version = root["version"].strVal;
    msg.type = root["type"].strVal;
    msg.status = root["status"].strVal;
    msg.deviceName = root["device_name"].strVal;
    msg.transport = root["transport"].strVal;
    msg.streamPort = static_cast<int>(root["stream_port"].numVal);
    
    const auto& ladder = root["selected_ladder"];
    if (ladder.isObject()) {
        msg.width = static_cast<int>(ladder["width"].numVal);
        msg.height = static_cast<int>(ladder["height"].numVal);
        msg.fps = static_cast<int>(ladder["fps"].numVal);
        msg.bitrate = static_cast<int>(ladder["bitrate"].numVal);
    }
    
    const auto& seqsVal = root["seqs"];
    if (seqsVal.isArray()) {
        for (const auto& item : seqsVal.arrVal) {
            if (item.isNumber()) {
                msg.seqs.push_back(static_cast<uint16_t>(item.numVal));
            }
        }
    }

    if (root["loss_fraction"].isNumber()) msg.lossFraction = root["loss_fraction"].numVal;
    if (root["jitter_ms"].isNumber()) msg.jitterMs = root["jitter_ms"].numVal;

    return msg;
}

std::string makeConnectMessage(int width, int height, int fps, const std::string& transport, int streamPort) {
    std::stringstream ss;
    ss << "{\"version\":\"1.0\",\"type\":\"connect\",\"selected_ladder\":{"
       << "\"width\":" << width << ",\"height\":" << height << ",\"fps\":" << fps
       << "},\"transport\":\"" << transport << "\",\"stream_port\":" << streamPort << "}";
    return ss.str();
}

std::string makeStartMessage() {
    return "{\"version\":\"1.0\",\"type\":\"start\"}";
}

std::string makeStopMessage() {
    return "{\"version\":\"1.0\",\"type\":\"stop\"}";
}

std::string makePingMessage() {
    return "{\"version\":\"1.0\",\"type\":\"ping\"}";
}

std::string makeNackMessage(const std::vector<uint16_t>& seqs) {
    std::stringstream ss;
    ss << "{\"version\":\"1.0\",\"type\":\"nack\",\"seqs\":[";
    for (size_t i = 0; i < seqs.size(); ++i) {
        ss << seqs[i];
        if (i + 1 < seqs.size()) ss << ",";
    }
    ss << "]}";
    return ss.str();
}

std::string makePliMessage() {
    return "{\"version\":\"1.0\",\"type\":\"pli\"}";
}

std::string makeFeedbackMessage(double lossFraction, double jitterMs) {
    std::stringstream ss;
    ss << "{\"version\":\"1.0\",\"type\":\"feedback\",\"loss_fraction\":" << lossFraction
       << ",\"jitter_ms\":" << jitterMs << "}";
    return ss.str();
}

} // namespace phonecam
