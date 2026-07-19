#pragma once
#include <string>
#include <vector>
#include <map>

namespace phonecam {

struct JsonValue {
    enum class Type { Null, Bool, Number, String, Array, Object };
    Type type = Type::Null;
    bool boolVal = false;
    double numVal = 0.0;
    std::string strVal;
    std::vector<JsonValue> arrVal;
    std::map<std::string, JsonValue> objVal;

    bool isNull() const { return type == Type::Null; }
    bool isBool() const { return type == Type::Bool; }
    bool isNumber() const { return type == Type::Number; }
    bool isString() const { return type == Type::String; }
    bool isArray() const { return type == Type::Array; }
    bool isObject() const { return type == Type::Object; }

    const JsonValue& operator[](const std::string& key) const {
        static const JsonValue nullVal;
        if (type != Type::Object) return nullVal;
        auto it = objVal.find(key);
        if (it == objVal.end()) return nullVal;
        return it->second;
    }

    const JsonValue& operator[](size_t index) const {
        static const JsonValue nullVal;
        if (type != Type::Array || index >= arrVal.size()) return nullVal;
        return arrVal[index];
    }
};

class JsonParser {
public:
    static JsonValue parse(const std::string& json);
};

struct ControlMessage {
    std::string version;
    std::string type;
    std::string status;
    std::string deviceName;
    std::string transport;
    int streamPort = 0;
    int width = 0;
    int height = 0;
    int fps = 0;
    int bitrate = 0;
    std::vector<uint16_t> seqs;
    double lossFraction = 0.0;
    double jitterMs = 0.0;
};

ControlMessage parseControlMessage(const std::string& jsonStr);
std::string makeConnectMessage(int width, int height, int fps, const std::string& transport, int streamPort);
std::string makeStartMessage();
std::string makeStopMessage();
std::string makePingMessage();
std::string makeNackMessage(const std::vector<uint16_t>& seqs);
std::string makePliMessage();
std::string makeFeedbackMessage(double lossFraction, double jitterMs);

} // namespace phonecam
