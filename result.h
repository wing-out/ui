#ifndef RESULT_H
#define RESULT_H

#include <QString>

class IResult
{
public:
    virtual ~IResult() {
        if (cause != nullptr) {
            delete cause;
            cause = nullptr;
        }
    };
    bool is_error() {
        return get_abstract_code() != 0;
    };
    virtual int get_abstract_code() = 0;
    QString description;
    IResult *cause;
};

// Result is a sloppy weird mix of `Result` from Rust, `error` from Go and laziness to have proper
// error handling in C++.
template <typename Enum> class Result : public IResult {
public:
    Result(
        Enum code
    ) : code(code) {}
    Result(
        Enum code, IResult *cause
    ) : code(code) {
        this->cause = cause;
    }
    Result(
        Enum code, QString description, IResult *cause = nullptr
    ) : code(code) {
        this->description = description;
        this->cause = cause;
    }
    int get_abstract_code() override {
        return int(code);
    }
    Enum code;
};

#endif // RESULT_H
