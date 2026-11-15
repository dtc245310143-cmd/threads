#include "VoiceBridge.h"
#include "audiocpp.h"
#include "sea_g2p.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <string>

namespace {
struct Voice {
    audiocpp_registry *registry = nullptr;
    audiocpp_model *model = nullptr;
    audiocpp_session *session = nullptr;
    sea_g2p *phonemizer = nullptr;
    std::string directory;
    ~Voice() {
        audiocpp_session_free(session);audiocpp_model_free(model);audiocpp_registry_free(registry);sea_g2p_close(phonemizer);
    }
};
void check(audiocpp_status status) { if(status != AUDIOCPP_OK) throw std::runtime_error(audiocpp_last_error()); }
void fail(char *output,size_t capacity,const char *message) { if(output && capacity) std::snprintf(output,capacity,"%s",message); }
void u16(std::ostream &out,uint16_t n) { const char b[2]={static_cast<char>(n),static_cast<char>(n>>8)};out.write(b,2); }
void u32(std::ostream &out,uint32_t n) { u16(out,static_cast<uint16_t>(n));u16(out,static_cast<uint16_t>(n>>16)); }
}
void *studio_voice_open(const char *directory,char *error,size_t capacity) {
    try {
        if(!directory) throw std::runtime_error("Missing voice directory");
        auto voice = std::make_unique<Voice>();voice->directory=directory;
        voice->phonemizer=sea_g2p_open((voice->directory+"/sea_g2p.bin").c_str());
        if(!voice->phonemizer) throw std::runtime_error(sea_g2p_last_error());
        check(audiocpp_registry_create(nullptr,&voice->registry));
        audiocpp_model_config config{};config.family_hint="vieneu_v3_turbo";
        check(audiocpp_model_load(voice->registry,(voice->directory+"/vieneu.gguf").c_str(),&config,nullptr,&voice->model));
        audiocpp_backend_config backend{"cpu",0,4};
        check(audiocpp_session_create(voice->model,"tts","offline",&backend,nullptr,&voice->session));
        return voice.release();
    } catch(const std::exception &e) { fail(error,capacity,e.what());return nullptr; }
}
int studio_voice_write(void *handle,const char *text,const char *destination,char *error,size_t capacity) {
    try {
        auto *voice=static_cast<Voice *>(handle);
        if(!voice || !text || !destination) throw std::runtime_error("Missing voice request");
        std::unique_ptr<char,decltype(&sea_g2p_string_free)> phones(sea_g2p_phonemize(voice->phonemizer,text,1),sea_g2p_string_free);
        if(!phones) throw std::runtime_error(sea_g2p_last_error());
        std::unique_ptr<audiocpp_request,decltype(&audiocpp_request_free)> request(audiocpp_request_create(),audiocpp_request_free);
        if(!request) throw std::runtime_error("Cannot allocate voice request");
        check(audiocpp_request_set_text(request.get(),phones.get(),nullptr));
        auto option=[&](const char *key,const std::string &value){check(audiocpp_request_set_option(request.get(),key,value.c_str()));};
        option("reference_codes_file",voice->directory+"/ref_codes.txt");
        option("speaker_embedding_file",voice->directory+"/speaker.emb.txt");
        option("max_tokens","900");option("text_chunk_size","120");
        option("temperature","0.8");option("top_k","25");option("top_p","0.95");option("repetition_penalty","1.2");
        audiocpp_result *raw=nullptr;check(audiocpp_session_run(voice->session,request.get(),&raw));
        std::unique_ptr<audiocpp_result,decltype(&audiocpp_result_free)> result(raw,audiocpp_result_free);
        const float *samples=nullptr;size_t frames=0;int rate=0,channels=0;
        check(audiocpp_result_audio(result.get(),&samples,&frames,&rate,&channels));
        if(!samples || frames==0 || rate!=48000 || channels<1 || channels>2 || frames>48000*1800) throw std::runtime_error("Invalid generated voice audio");
        std::ofstream output(destination,std::ios::binary);
        if(!output) throw std::runtime_error("Cannot save voice audio");
        const auto bytes=static_cast<uint32_t>(frames*channels*2);
        output.write("RIFF",4);u32(output,36+bytes);output.write("WAVEfmt ",8);u32(output,16);u16(output,1);u16(output,static_cast<uint16_t>(channels));
        u32(output,static_cast<uint32_t>(rate));u32(output,static_cast<uint32_t>(rate*channels*2));u16(output,static_cast<uint16_t>(channels*2));u16(output,16);output.write("data",4);u32(output,bytes);
        for(size_t i=0;i<frames*channels;++i) {
            if(!std::isfinite(samples[i])) throw std::runtime_error("Non-finite generated sample");
            const auto sample=static_cast<int16_t>(std::lrint(std::max(-1.0f,std::min(1.0f,samples[i]))*32767.0f));u16(output,static_cast<uint16_t>(sample));
        }
        output.close();if(!output) throw std::runtime_error("Voice file write failed");return 1;
    } catch(const std::exception &e) { fail(error,capacity,e.what());return 0; }
}
void studio_voice_close(void *handle) { delete static_cast<Voice *>(handle); }
