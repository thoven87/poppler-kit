// poppler_bridge.cpp — C++ implementation of the pure-C poppler_c_api.h
//
// Compiled as C++17; never seen by Swift.  Swift targets import only the
// pure-C header (poppler_c_api.h) so they need no C++ interop mode.
//
// String-returning functions use per-function thread_local std::string
// buffers.  Swift always calls String(cString:) which copies immediately,
// so the TLS buffer is safe to reuse on the next call from the same thread.

#include <poppler-version.h>
#include <poppler-document.h>
#include <poppler-page.h>
#include <poppler-image.h>
#include <poppler-global.h>
#include <poppler-page-renderer.h>
#include <poppler-toc.h>
#include <poppler-embedded-file.h>
#include <poppler-destination.h>
#include <poppler-page-transition.h>
#include <poppler-font.h>
#include <string>
#include <map>
#include <vector>
#include <utility>

#include "poppler_c_api.h"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Version check
// ─────────────────────────────────────────────────────────────────────────────

#define POPPLER_KIT_ENCODE(maj, min, mic) ((maj)*10000 + (min)*100 + (mic))
#define POPPLER_KIT_VERSION_INSTALLED \
    POPPLER_KIT_ENCODE(POPPLER_VERSION_MAJOR, POPPLER_VERSION_MINOR, POPPLER_VERSION_MICRO)
#define POPPLER_KIT_VERSION_MIN  POPPLER_KIT_ENCODE(26, 4, 0)

static_assert(
    POPPLER_KIT_VERSION_INSTALLED >= POPPLER_KIT_VERSION_MIN,
    "PopplerKit requires poppler >= 26.04.0. "
    "macOS: brew install pkg-config poppler  "
    "Linux: build from source https://poppler.freedesktop.org/");

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Opaque handle cast helpers
//
// Each opaque handle pointer is reinterpreted as the matching C++ heap object.
// Lifetimes are always managed by the corresponding delete_* function.
// ─────────────────────────────────────────────────────────────────────────────

static inline poppler::document*      toDoc    (PopplerDocPtr p)  noexcept { return reinterpret_cast<poppler::document*>(p); }
static inline poppler::page*          toPage   (PopplerPagePtr p) noexcept { return reinterpret_cast<poppler::page*>(p); }
static inline PopplerDocPtr           fromDoc  (poppler::document* p) noexcept { return reinterpret_cast<PopplerDocPtr>(p); }
static inline PopplerPagePtr          fromPage (poppler::page* p)     noexcept { return reinterpret_cast<PopplerPagePtr>(p); }

static inline poppler::page_renderer* toRenderer  (PopplerRendererPtr p)       noexcept { return reinterpret_cast<poppler::page_renderer*>(p); }
static inline poppler::image*         toImage     (PopplerImagePtr p)           noexcept { return reinterpret_cast<poppler::image*>(p); }
static inline PopplerRendererPtr      fromRenderer(poppler::page_renderer* p)   noexcept { return reinterpret_cast<PopplerRendererPtr>(p); }
static inline PopplerImagePtr         fromImage   (poppler::image* p)           noexcept { return reinterpret_cast<PopplerImagePtr>(p); }

static inline std::vector<poppler::text_box>* toTextList  (PopplerTextBoxListPtr p) noexcept { return reinterpret_cast<std::vector<poppler::text_box>*>(p); }
static inline poppler::text_box*              toTextBox   (PopplerTextBoxPtr p)     noexcept { return reinterpret_cast<poppler::text_box*>(p); }
static inline PopplerTextBoxListPtr           fromTextList(std::vector<poppler::text_box>* p) noexcept { return reinterpret_cast<PopplerTextBoxListPtr>(p); }

static inline poppler::toc*                    toTOC     (PopplerTOCPtr p)         noexcept { return reinterpret_cast<poppler::toc*>(p); }
static inline poppler::toc_item*               toTOCItem (PopplerTOCItemPtr p)     noexcept { return reinterpret_cast<poppler::toc_item*>(p); }
static inline std::vector<poppler::toc_item*>* toTOCList (PopplerTOCItemListPtr p) noexcept { return reinterpret_cast<std::vector<poppler::toc_item*>*>(p); }
static inline PopplerTOCPtr                    fromTOC   (poppler::toc* p)         noexcept { return reinterpret_cast<PopplerTOCPtr>(p); }
static inline PopplerTOCItemListPtr            fromTOCList(std::vector<poppler::toc_item*>* p) noexcept { return reinterpret_cast<PopplerTOCItemListPtr>(p); }

static inline std::vector<poppler::embedded_file*>* toFileList  (PopplerEmbeddedFileListPtr p) noexcept { return reinterpret_cast<std::vector<poppler::embedded_file*>*>(p); }
static inline poppler::embedded_file*               toFile      (PopplerEmbeddedFilePtr p)     noexcept { return reinterpret_cast<poppler::embedded_file*>(p); }
static inline poppler::byte_array*                  toByteArr   (PopplerByteArrayPtr p)        noexcept { return reinterpret_cast<poppler::byte_array*>(p); }
static inline PopplerEmbeddedFileListPtr            fromFileList(std::vector<poppler::embedded_file*>* p) noexcept { return reinterpret_cast<PopplerEmbeddedFileListPtr>(p); }
static inline PopplerByteArrayPtr                   fromByteArr (poppler::byte_array* p)       noexcept { return reinterpret_cast<PopplerByteArrayPtr>(p); }

static inline std::map<std::string, poppler::destination>*                toDestMap (PopplerDestinationMapPtr p)  noexcept { return reinterpret_cast<std::map<std::string, poppler::destination>*>(p); }
static inline std::vector<std::pair<std::string, poppler::destination*>>* toDestList(PopplerDestinationListPtr p) noexcept { return reinterpret_cast<std::vector<std::pair<std::string, poppler::destination*>>*>(p); }
static inline poppler::destination*                                       toDest    (PopplerDestinationPtr p)     noexcept { return reinterpret_cast<poppler::destination*>(p); }
static inline PopplerDestinationMapPtr  fromDestMap (std::map<std::string, poppler::destination>* p) noexcept { return reinterpret_cast<PopplerDestinationMapPtr>(p); }
static inline PopplerDestinationListPtr fromDestList(std::vector<std::pair<std::string, poppler::destination*>>* p) noexcept { return reinterpret_cast<PopplerDestinationListPtr>(p); }

static inline poppler::font_iterator*          toFontIter(PopplerFontIteratorPtr p) noexcept { return reinterpret_cast<poppler::font_iterator*>(p); }
static inline std::vector<poppler::font_info>* toFontList(PopplerFontInfoListPtr p) noexcept { return reinterpret_cast<std::vector<poppler::font_info>*>(p); }
static inline poppler::font_info*              toFont    (PopplerFontInfoPtr p)     noexcept { return reinterpret_cast<poppler::font_info*>(p); }
static inline PopplerFontIteratorPtr           fromFontIter(poppler::font_iterator* p)          noexcept { return reinterpret_cast<PopplerFontIteratorPtr>(p); }
static inline PopplerFontInfoListPtr           fromFontList(std::vector<poppler::font_info>* p) noexcept { return reinterpret_cast<PopplerFontInfoListPtr>(p); }

static inline poppler::page_transition* toTransition  (PopplerPageTransitionPtr p) noexcept { return reinterpret_cast<poppler::page_transition*>(p); }
static inline PopplerPageTransitionPtr  fromTransition(poppler::page_transition* p) noexcept { return reinterpret_cast<PopplerPageTransitionPtr>(p); }

static inline std::vector<std::string>* toStrList  (PopplerStringListPtr p) noexcept { return reinterpret_cast<std::vector<std::string>*>(p); }
static inline PopplerStringListPtr      fromStrList(std::vector<std::string>* p) noexcept { return reinterpret_cast<PopplerStringListPtr>(p); }

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Document Loading
// ─────────────────────────────────────────────────────────────────────────────

PopplerDocPtr poppler_document_load_from_file(const char* file_name) {
    if (!file_name) return nullptr;
    return fromDoc(poppler::document::load_from_file(file_name));
}

PopplerDocPtr poppler_document_load_from_raw_data(const char* file_data, int length) {
    if (!file_data || length <= 0) return nullptr;
    return fromDoc(poppler::document::load_from_raw_data(file_data, length));
}

PopplerDocPtr poppler_document_load_from_file_with_password(
    const char* file_name, const char* owner_password, const char* user_password)
{
    if (!file_name) return nullptr;
    return fromDoc(poppler::document::load_from_file(
        std::string(file_name),
        owner_password ? std::string(owner_password) : std::string(),
        user_password  ? std::string(user_password)  : std::string()
    ));
}

PopplerDocPtr poppler_document_load_from_raw_data_with_password(
    const char* file_data, int length,
    const char* owner_password, const char* user_password)
{
    if (!file_data || length <= 0) return nullptr;
    return fromDoc(poppler::document::load_from_raw_data(
        file_data, length,
        owner_password ? std::string(owner_password) : std::string(),
        user_password  ? std::string(user_password)  : std::string()
    ));
}

void poppler_delete_document(PopplerDocPtr doc) {
    delete toDoc(doc);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Document Properties
// ─────────────────────────────────────────────────────────────────────────────

int poppler_document_get_pages(PopplerDocPtr doc) {
    return toDoc(doc)->pages();
}

void poppler_document_get_pdf_version(PopplerDocPtr doc, int* major, int* minor) {
    toDoc(doc)->get_pdf_version(major, minor);
}

int poppler_document_get_page_layout(PopplerDocPtr doc) {
    return static_cast<int>(toDoc(doc)->page_layout());
}

int poppler_document_get_page_mode(PopplerDocPtr doc) {
    return static_cast<int>(toDoc(doc)->page_mode());
}

int poppler_document_get_form_type(PopplerDocPtr doc) {
    return static_cast<int>(toDoc(doc)->form_type());
}

bool poppler_document_is_encrypted(PopplerDocPtr doc) {
    return toDoc(doc)->is_encrypted();
}

bool poppler_document_is_locked(PopplerDocPtr doc) {
    return toDoc(doc)->is_locked();
}

bool poppler_document_is_linearized(PopplerDocPtr doc) {
    return toDoc(doc)->is_linearized();
}

bool poppler_document_has_embedded_files(PopplerDocPtr doc) {
    return toDoc(doc)->has_embedded_files();
}

bool poppler_document_has_javascript(PopplerDocPtr doc) {
    return toDoc(doc)->has_javascript();
}

bool poppler_document_has_permission(PopplerDocPtr doc, int perm) {
    return toDoc(doc)->has_permission(static_cast<poppler::permission_enum>(perm));
}

bool poppler_document_has_pdf_id(PopplerDocPtr doc) {
    std::string p, u;
    return toDoc(doc)->get_pdf_id(&p, &u);
}

bool poppler_document_unlock(PopplerDocPtr doc, const char* owner_password, const char* user_password) {
    return toDoc(doc)->unlock(
        owner_password ? std::string(owner_password) : std::string(),
        user_password  ? std::string(user_password)  : std::string()
    );
}

bool poppler_document_save(PopplerDocPtr doc, const char* file_path) {
    if (!file_path) return false;
    return toDoc(doc)->save(std::string(file_path));
}

bool poppler_document_save_a_copy(PopplerDocPtr doc, const char* file_path) {
    if (!file_path) return false;
    return toDoc(doc)->save_a_copy(std::string(file_path));
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Document Metadata (string returns via TLS buffers)
// ─────────────────────────────────────────────────────────────────────────────

const char* poppler_document_get_title(PopplerDocPtr doc) {
    thread_local std::string buf;
    poppler::ustring u = toDoc(doc)->get_title();
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

const char* poppler_document_get_author(PopplerDocPtr doc) {
    thread_local std::string buf;
    poppler::ustring u = toDoc(doc)->get_author();
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

const char* poppler_document_get_subject(PopplerDocPtr doc) {
    thread_local std::string buf;
    poppler::ustring u = toDoc(doc)->get_subject();
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

const char* poppler_document_get_keywords(PopplerDocPtr doc) {
    thread_local std::string buf;
    poppler::ustring u = toDoc(doc)->get_keywords();
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

const char* poppler_document_get_creator(PopplerDocPtr doc) {
    thread_local std::string buf;
    poppler::ustring u = toDoc(doc)->get_creator();
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

const char* poppler_document_get_producer(PopplerDocPtr doc) {
    thread_local std::string buf;
    poppler::ustring u = toDoc(doc)->get_producer();
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

const char* poppler_document_get_metadata(PopplerDocPtr doc) {
    thread_local std::string buf;
    poppler::ustring u = toDoc(doc)->metadata();
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

const char* poppler_document_get_permanent_id(PopplerDocPtr doc) {
    thread_local std::string buf;
    std::string p, u;
    toDoc(doc)->get_pdf_id(&p, &u);
    buf = std::move(p);
    return buf.c_str();
}

const char* poppler_document_get_update_id(PopplerDocPtr doc) {
    thread_local std::string buf;
    std::string p, u;
    toDoc(doc)->get_pdf_id(&p, &u);
    buf = std::move(u);
    return buf.c_str();
}

long poppler_document_get_creation_date(PopplerDocPtr doc) {
    return static_cast<long>(toDoc(doc)->get_creation_date_t());
}

long poppler_document_get_modification_date(PopplerDocPtr doc) {
    return static_cast<long>(toDoc(doc)->get_modification_date_t());
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Info Dictionary
// ─────────────────────────────────────────────────────────────────────────────

PopplerStringListPtr poppler_document_get_info_keys(PopplerDocPtr doc) {
    auto vec = new std::vector<std::string>(toDoc(doc)->info_keys());
    return fromStrList(vec);
}

void poppler_delete_string_list(PopplerStringListPtr list) {
    delete toStrList(list);
}

int poppler_string_list_get_size(PopplerStringListPtr list) {
    return static_cast<int>(toStrList(list)->size());
}

const char* poppler_string_list_get_item(PopplerStringListPtr list, int index) {
    // Returns a pointer into the vector's own string storage.
    // Valid as long as the list is alive and not modified.
    return (*toStrList(list))[index].c_str();
}

const char* poppler_document_get_info_key(PopplerDocPtr doc, const char* key) {
    thread_local std::string buf;
    if (!key) { buf.clear(); return buf.c_str(); }
    poppler::ustring uval = toDoc(doc)->info_key(std::string(key));
    poppler::byte_array b = uval.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Pages
// ─────────────────────────────────────────────────────────────────────────────

PopplerPagePtr poppler_document_create_page(PopplerDocPtr doc, int index) {
    return fromPage(toDoc(doc)->create_page(index));
}

PopplerPagePtr poppler_document_create_page_by_label(PopplerDocPtr doc, const char* label) {
    if (!label) return nullptr;
    poppler::ustring ulabel = poppler::ustring::from_utf8(label, -1);
    return fromPage(toDoc(doc)->create_page(ulabel));
}

void poppler_delete_page(PopplerPagePtr page) {
    delete toPage(page);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Page Properties
// ─────────────────────────────────────────────────────────────────────────────

PopplerRect poppler_page_get_media_box(PopplerPagePtr page) {
    poppler::rectf r = toPage(page)->page_rect(poppler::media_box);
    return { r.left(), r.top(), r.right(), r.bottom() };
}

PopplerRect poppler_page_get_page_rect(PopplerPagePtr page, int box_type) {
    auto box = static_cast<poppler::page_box_enum>(box_type);
    poppler::rectf r = toPage(page)->page_rect(box);
    return { r.left(), r.top(), r.right(), r.bottom() };
}

int poppler_page_get_orientation(PopplerPagePtr page) {
    return static_cast<int>(toPage(page)->orientation());
}

double poppler_page_get_duration(PopplerPagePtr page) {
    return toPage(page)->duration();
}

const char* poppler_page_get_label(PopplerPagePtr page) {
    thread_local std::string buf;
    poppler::ustring u = toPage(page)->label();
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Text Extraction
// ─────────────────────────────────────────────────────────────────────────────

const char* poppler_page_text_utf8(PopplerPagePtr page) {
    thread_local std::string buf;
    poppler::ustring u = toPage(page)->text();
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

const char* poppler_page_text_utf8_with_layout(PopplerPagePtr page, int layout) {
    thread_local std::string buf;
    auto* p = toPage(page);
    auto mode = static_cast<poppler::page::text_layout_enum>(layout);
    poppler::ustring u = p->text(p->page_rect(), mode);
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

const char* poppler_page_text_in_rect(
    PopplerPagePtr page, double left, double top, double right, double bottom)
{
    thread_local std::string buf;
    auto* p = toPage(page);
    poppler::rectf r(left, top, right - left, bottom - top);
    poppler::ustring u = p->text(r);
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

const char* poppler_page_text_in_rect_with_layout(
    PopplerPagePtr page, double left, double top, double right, double bottom, int layout)
{
    thread_local std::string buf;
    auto* p = toPage(page);
    auto mode = static_cast<poppler::page::text_layout_enum>(layout);
    poppler::rectf r(left, top, right - left, bottom - top);
    poppler::ustring u = p->text(r, mode);
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

bool poppler_page_search(
    PopplerPagePtr page, const char* text,
    double* left, double* top, double* right, double* bottom,
    int direction, int case_sensitivity)
{
    if (!text || !left || !top || !right || !bottom) return false;
    auto* p = toPage(page);
    poppler::ustring usearch = poppler::ustring::from_utf8(text, -1);

    double w = *right - *left, h = *bottom - *top;
    poppler::rectf r(*left, *top, w > 0 ? w : 0, h > 0 ? h : 0);

    bool found = p->search(
        usearch, r,
        static_cast<poppler::page::search_direction_enum>(direction),
        static_cast<poppler::case_sensitivity_enum>(case_sensitivity));

    if (found) {
        *left = r.left(); *top = r.top(); *right = r.right(); *bottom = r.bottom();
    }
    return found;
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Text Boxes
// ─────────────────────────────────────────────────────────────────────────────

PopplerTextBoxListPtr poppler_page_get_text_list(PopplerPagePtr page) {
    auto list = new std::vector<poppler::text_box>(
        toPage(page)->text_list(poppler::page::text_list_include_font));
    return fromTextList(list);
}

void poppler_delete_text_list(PopplerTextBoxListPtr list) {
    delete toTextList(list);
}

int poppler_text_list_get_size(PopplerTextBoxListPtr list) {
    return static_cast<int>(toTextList(list)->size());
}

PopplerTextBoxPtr poppler_text_list_get_item(PopplerTextBoxListPtr list, int index) {
    auto& vec = *toTextList(list);
    return reinterpret_cast<PopplerTextBoxPtr>(&vec[index]);
}

const char* poppler_text_box_get_text_utf8(PopplerTextBoxPtr box) {
    thread_local std::string buf;
    poppler::ustring u = toTextBox(box)->text();
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

PopplerRect poppler_text_box_get_bbox(PopplerTextBoxPtr box) {
    poppler::rectf r = toTextBox(box)->bbox();
    return { r.left(), r.top(), r.right(), r.bottom() };
}

double poppler_text_box_get_font_size(PopplerTextBoxPtr box) {
    return toTextBox(box)->get_font_size();
}

const char* poppler_text_box_get_font_name(PopplerTextBoxPtr box) {
    thread_local std::string buf;
    buf = toTextBox(box)->get_font_name();
    return buf.c_str();
}

int poppler_text_box_get_rotation(PopplerTextBoxPtr box) {
    return toTextBox(box)->rotation();
}

bool poppler_text_box_has_space_after(PopplerTextBoxPtr box) {
    return toTextBox(box)->has_space_after();
}

bool poppler_text_box_has_font_info(PopplerTextBoxPtr box) {
    return toTextBox(box)->has_font_info();
}

int poppler_text_box_get_text_length(PopplerTextBoxPtr box) {
    return static_cast<int>(toTextBox(box)->text().size());
}

PopplerRect poppler_text_box_get_char_bbox(PopplerTextBoxPtr box, int index) {
    poppler::rectf r = toTextBox(box)->char_bbox(static_cast<size_t>(index));
    return { r.left(), r.top(), r.right(), r.bottom() };
}

int poppler_text_box_get_wmode(PopplerTextBoxPtr box, int index) {
    return static_cast<int>(toTextBox(box)->get_wmode(index));
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Image Rendering
// ─────────────────────────────────────────────────────────────────────────────

PopplerRendererPtr poppler_renderer_create(void) {
    return fromRenderer(new poppler::page_renderer());
}

void poppler_renderer_delete(PopplerRendererPtr renderer) {
    delete toRenderer(renderer);
}

void poppler_renderer_set_render_hint(PopplerRendererPtr renderer, int hint, bool on) {
    toRenderer(renderer)->set_render_hint(
        static_cast<poppler::page_renderer::render_hint>(hint), on);
}

void poppler_renderer_set_antialiasing(PopplerRendererPtr renderer, bool on) {
    toRenderer(renderer)->set_render_hint(poppler::page_renderer::antialiasing, on);
}

void poppler_renderer_set_text_antialiasing(PopplerRendererPtr renderer, bool on) {
    toRenderer(renderer)->set_render_hint(poppler::page_renderer::text_antialiasing, on);
}

void poppler_renderer_set_text_hinting(PopplerRendererPtr renderer, bool on) {
    toRenderer(renderer)->set_render_hint(poppler::page_renderer::text_hinting, on);
}

PopplerImagePtr poppler_renderer_render_page(
    PopplerRendererPtr renderer, PopplerPagePtr page, double xres, double yres)
{
    poppler::image img = toRenderer(renderer)->render_page(toPage(page), xres, yres);
    return fromImage(new poppler::image(img));
}

void poppler_image_delete(PopplerImagePtr image) {
    delete toImage(image);
}

bool poppler_image_is_valid(PopplerImagePtr image) {
    return toImage(image)->is_valid();
}

int poppler_image_get_width(PopplerImagePtr image) {
    return toImage(image)->width();
}

int poppler_image_get_height(PopplerImagePtr image) {
    return toImage(image)->height();
}

int poppler_image_get_bytes_per_row(PopplerImagePtr image) {
    return toImage(image)->bytes_per_row();
}

const char* poppler_image_get_data(PopplerImagePtr image) {
    return toImage(image)->const_data();
}

int poppler_image_get_format(PopplerImagePtr image) {
    return static_cast<int>(toImage(image)->format());
}

bool poppler_image_save_to_path(
    PopplerImagePtr image, const char* file_path, const char* format, int dpi)
{
    if (!file_path || !format) return false;
    return toImage(image)->save(std::string(file_path), std::string(format), dpi);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Table of Contents (TOC)
// ─────────────────────────────────────────────────────────────────────────────

PopplerTOCPtr poppler_document_create_toc(PopplerDocPtr doc) {
    return fromTOC(toDoc(doc)->create_toc());
}

void poppler_delete_toc(PopplerTOCPtr toc) {
    delete toTOC(toc);
}

PopplerTOCItemPtr poppler_toc_get_root(PopplerTOCPtr toc) {
    return reinterpret_cast<PopplerTOCItemPtr>(toTOC(toc)->root());
}

const char* poppler_toc_item_get_title(PopplerTOCItemPtr item) {
    thread_local std::string buf;
    poppler::ustring u = toTOCItem(item)->title();
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

bool poppler_toc_item_is_open(PopplerTOCItemPtr item) {
    return toTOCItem(item)->is_open();
}

PopplerTOCItemListPtr poppler_toc_item_get_children(PopplerTOCItemPtr item) {
    auto list = new std::vector<poppler::toc_item*>(toTOCItem(item)->children());
    return fromTOCList(list);
}

void poppler_delete_toc_item_list(PopplerTOCItemListPtr list) {
    delete toTOCList(list);
}

int poppler_toc_item_list_get_size(PopplerTOCItemListPtr list) {
    return static_cast<int>(toTOCList(list)->size());
}

PopplerTOCItemPtr poppler_toc_item_list_get_item(PopplerTOCItemListPtr list, int index) {
    auto& vec = *toTOCList(list);
    return reinterpret_cast<PopplerTOCItemPtr>(vec[index]);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Embedded Files
// ─────────────────────────────────────────────────────────────────────────────

PopplerEmbeddedFileListPtr poppler_document_get_embedded_files(PopplerDocPtr doc) {
    auto list = new std::vector<poppler::embedded_file*>(toDoc(doc)->embedded_files());
    return fromFileList(list);
}

void poppler_delete_embedded_file_list(PopplerEmbeddedFileListPtr list) {
    auto vec = toFileList(list);
    for (auto f : *vec) { delete f; }
    delete vec;
}

int poppler_embedded_file_list_get_size(PopplerEmbeddedFileListPtr list) {
    return static_cast<int>(toFileList(list)->size());
}

PopplerEmbeddedFilePtr poppler_embedded_file_list_get_item(
    PopplerEmbeddedFileListPtr list, int index)
{
    auto& vec = *toFileList(list);
    return reinterpret_cast<PopplerEmbeddedFilePtr>(vec[index]);
}

bool poppler_embedded_file_is_valid(PopplerEmbeddedFilePtr file) {
    return toFile(file)->is_valid();
}

const char* poppler_embedded_file_get_name(PopplerEmbeddedFilePtr file) {
    thread_local std::string buf;
    poppler::ustring u = toFile(file)->unicodeName();
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

const char* poppler_embedded_file_get_mime_type(PopplerEmbeddedFilePtr file) {
    thread_local std::string buf;
    buf = toFile(file)->mime_type();
    return buf.c_str();
}

const char* poppler_embedded_file_get_description(PopplerEmbeddedFilePtr file) {
    thread_local std::string buf;
    poppler::ustring u = toFile(file)->description();
    poppler::byte_array b = u.to_utf8();
    buf.assign(b.begin(), b.end());
    return buf.c_str();
}

const char* poppler_embedded_file_get_checksum(PopplerEmbeddedFilePtr file) {
    thread_local std::string buf;
    poppler::byte_array raw = toFile(file)->checksum();
    if (raw.empty()) { buf.clear(); return buf.c_str(); }
    static const char hex[] = "0123456789abcdef";
    buf.clear();
    buf.reserve(raw.size() * 2);
    for (unsigned char c : raw) {
        buf += hex[c >> 4];
        buf += hex[c & 0xf];
    }
    return buf.c_str();
}

int poppler_embedded_file_get_size(PopplerEmbeddedFilePtr file) {
    return toFile(file)->size();
}

long poppler_embedded_file_get_creation_date(PopplerEmbeddedFilePtr file) {
    return static_cast<long>(toFile(file)->creation_date_t());
}

long poppler_embedded_file_get_modification_date(PopplerEmbeddedFilePtr file) {
    return static_cast<long>(toFile(file)->modification_date_t());
}

PopplerByteArrayPtr poppler_embedded_file_get_data(PopplerEmbeddedFilePtr file) {
    auto arr = new poppler::byte_array(toFile(file)->data());
    return fromByteArr(arr);
}

void poppler_delete_byte_array(PopplerByteArrayPtr arr) {
    delete toByteArr(arr);
}

const char* poppler_byte_array_get_data(PopplerByteArrayPtr arr) {
    return toByteArr(arr)->data();
}

int poppler_byte_array_get_size(PopplerByteArrayPtr arr) {
    return static_cast<int>(toByteArr(arr)->size());
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Destinations
// ─────────────────────────────────────────────────────────────────────────────

PopplerDestinationMapPtr poppler_document_create_destination_map(PopplerDocPtr doc) {
    auto m = new std::map<std::string, poppler::destination>(
        toDoc(doc)->create_destination_map());
    return fromDestMap(m);
}

void poppler_delete_destination_map(PopplerDestinationMapPtr map) {
    delete toDestMap(map);
}

PopplerDestinationListPtr poppler_destination_map_to_list(PopplerDestinationMapPtr map) {
    auto vec = new std::vector<std::pair<std::string, poppler::destination*>>();
    for (auto& pair : *toDestMap(map)) {
        vec->push_back({ pair.first, &pair.second });
    }
    return fromDestList(vec);
}

void poppler_delete_destination_list(PopplerDestinationListPtr list) {
    delete toDestList(list);
}

int poppler_destination_list_get_size(PopplerDestinationListPtr list) {
    return static_cast<int>(toDestList(list)->size());
}

const char* poppler_destination_list_get_name(PopplerDestinationListPtr list, int index) {
    // Returns a pointer into the vector's own string storage.
    // Valid as long as the list is alive and not modified.
    return (*toDestList(list))[index].first.c_str();
}

PopplerDestinationPtr poppler_destination_list_get_dest(
    PopplerDestinationListPtr list, int index)
{
    return reinterpret_cast<PopplerDestinationPtr>((*toDestList(list))[index].second);
}

int poppler_destination_get_page_number(PopplerDestinationPtr dest) {
    return toDest(dest)->page_number();
}

double poppler_destination_get_left(PopplerDestinationPtr dest) {
    return toDest(dest)->left();
}

double poppler_destination_get_top(PopplerDestinationPtr dest) {
    return toDest(dest)->top();
}

double poppler_destination_get_zoom(PopplerDestinationPtr dest) {
    return toDest(dest)->zoom();
}

int poppler_destination_get_type(PopplerDestinationPtr dest) {
    return static_cast<int>(toDest(dest)->type());
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Fonts
// ─────────────────────────────────────────────────────────────────────────────

PopplerFontIteratorPtr poppler_document_create_font_iterator(PopplerDocPtr doc, int start_page) {
    return fromFontIter(toDoc(doc)->create_font_iterator(start_page));
}

void poppler_delete_font_iterator(PopplerFontIteratorPtr iter) {
    delete toFontIter(iter);
}

bool poppler_font_iterator_has_next(PopplerFontIteratorPtr iter) {
    return toFontIter(iter)->has_next();
}

PopplerFontInfoListPtr poppler_font_iterator_next(PopplerFontIteratorPtr iter) {
    auto vec = new std::vector<poppler::font_info>(toFontIter(iter)->next());
    return fromFontList(vec);
}

void poppler_delete_font_info_list(PopplerFontInfoListPtr list) {
    delete toFontList(list);
}

int poppler_font_info_list_get_size(PopplerFontInfoListPtr list) {
    return static_cast<int>(toFontList(list)->size());
}

PopplerFontInfoPtr poppler_font_info_list_get_item(PopplerFontInfoListPtr list, int index) {
    return reinterpret_cast<PopplerFontInfoPtr>(&(*toFontList(list))[index]);
}

const char* poppler_font_info_get_name(PopplerFontInfoPtr font) {
    thread_local std::string buf;
    buf = toFont(font)->name();
    return buf.c_str();
}

const char* poppler_font_info_get_file(PopplerFontInfoPtr font) {
    thread_local std::string buf;
    buf = toFont(font)->file();
    return buf.c_str();
}

bool poppler_font_info_is_embedded(PopplerFontInfoPtr font) {
    return toFont(font)->is_embedded();
}

bool poppler_font_info_is_subset(PopplerFontInfoPtr font) {
    return toFont(font)->is_subset();
}

int poppler_font_info_get_type(PopplerFontInfoPtr font) {
    return static_cast<int>(toFont(font)->type());
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Page Transitions
// ─────────────────────────────────────────────────────────────────────────────

PopplerPageTransitionPtr poppler_page_get_transition(PopplerPagePtr page) {
    return fromTransition(toPage(page)->transition());
}

void poppler_delete_page_transition(PopplerPageTransitionPtr transition) {
    delete toTransition(transition);
}

int poppler_page_transition_get_type(PopplerPageTransitionPtr transition) {
    return static_cast<int>(toTransition(transition)->type());
}

double poppler_page_transition_get_duration(PopplerPageTransitionPtr transition) {
    return toTransition(transition)->durationReal();
}

int poppler_page_transition_get_alignment(PopplerPageTransitionPtr transition) {
    return static_cast<int>(toTransition(transition)->alignment());
}

int poppler_page_transition_get_motion_direction(PopplerPageTransitionPtr transition) {
    return static_cast<int>(toTransition(transition)->direction());
}

int poppler_page_transition_get_angle(PopplerPageTransitionPtr transition) {
    return static_cast<int>(toTransition(transition)->angle());
}

double poppler_page_transition_get_scale(PopplerPageTransitionPtr transition) {
    return toTransition(transition)->scale();
}

bool poppler_page_transition_is_rectangular(PopplerPageTransitionPtr transition) {
    return toTransition(transition)->is_rectangular();
}
