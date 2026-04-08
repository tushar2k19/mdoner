# frozen_string_literal: true

require 'test_helper'

class HtmlTableToResizableTableTest < ActiveSupport::TestCase
  test 'convert_or_preserve keeps rowspan colspan and colgroup for word-like tables' do
    html = <<~HTML
      <table width="100%" cellspacing="0" cellpadding="9">
        <colgroup><col width="57"/><col width="40"/></colgroup>
        <tr>
          <td rowspan="3">Scheme</td>
          <td colspan="2">Weekly targets</td>
        </tr>
        <tr>
          <td>Tar</td>
          <td>Exp.</td>
        </tr>
        <tr>
          <td>1</td>
          <td>2</td>
        </tr>
      </table>
    HTML
    frag = Nokogiri::HTML::DocumentFragment.parse(html)
    tbl = frag.at_css('table')
    out = Import::HtmlTableToResizableTable.convert_or_preserve(tbl)

    assert_includes out, 'dashboard-import-table'
    assert_includes out, 'overflow-x: auto'
    assert_includes out, 'rowspan'
    assert_includes out, 'colspan'
    assert_includes out, 'colgroup'
    assert_includes out, 'col'
  end

  test 'convert_or_preserve removes empty rows in libreoffice-style merged tables' do
    html = <<~HTML
      <table cellspacing="0" cellpadding="9">
        <tr>
          <td rowspan="3">Scheme</td>
          <td rowspan="3">RE 25-26</td>
          <td colspan="2">Week 1</td>
        </tr>
        <tr></tr>
        <tr></tr>
        <tr>
          <td>Tar</td>
          <td>Exp.</td>
        </tr>
      </table>
    HTML

    out = Import::HtmlTableToResizableTable.convert_or_preserve(Nokogiri::HTML::DocumentFragment.parse(html).at_css('table'))
    frag = Nokogiri::HTML::DocumentFragment.parse(out)

    assert_equal 2, frag.css('table tr').length
    assert_equal 0, frag.css('table tr').count { |tr| tr.css('th,td').empty? }
    assert_includes out, 'dashboard-import-table'
  end

  test 'convert_or_preserve still produces resizable-table for simple grid' do
    html = <<~HTML
      <table>
        <tr><th>A</th><th>B</th></tr>
        <tr><td>1</td><td>2</td></tr>
      </table>
    HTML
    frag = Nokogiri::HTML::DocumentFragment.parse(html)
    out = Import::HtmlTableToResizableTable.convert_or_preserve(frag.at_css('table'))

    assert_includes out, 'resizable-table'
    refute_includes out, 'dashboard-import-table'
  end

  test 'normalize_complex_tables_in_html wraps and normalizes only complex tables' do
    html = <<~HTML
      <p>before</p>
      <table>
        <tr><td rowspan="2">A</td><td>B</td></tr>
        <tr></tr>
      </table>
      <table>
        <tr><td>X</td><td>Y</td></tr>
      </table>
    HTML

    out = Import::HtmlTableToResizableTable.normalize_complex_tables_in_html(html)
    frag = Nokogiri::HTML::DocumentFragment.parse(out)
    tables = frag.css('table')

    assert_equal 2, tables.length
    assert tables.first['class'].to_s.include?('dashboard-import-table')
    refute tables.last['class'].to_s.include?('dashboard-import-table')
    assert_equal 1, tables.first.css('tr').length
    assert_equal 1, frag.css('div[style*="overflow-x: auto"]').length
  end
end
