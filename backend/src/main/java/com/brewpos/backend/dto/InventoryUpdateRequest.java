package com.brewpos.backend.dto;

public class InventoryUpdateRequest {

    private String  barcode;
    private Integer buyPrice;
    private Integer reorderLevel;
    private String  unit;
    private Integer stockQty;

    // ── Getters ──────────────────────────────────────────────

    public String  getBarcode()      { return barcode; }
    public Integer getBuyPrice()     { return buyPrice; }
    public Integer getReorderLevel() { return reorderLevel; }
    public String  getUnit()         { return unit; }
    public Integer getStockQty()     { return stockQty; }

    // ── Setters ──────────────────────────────────────────────

    public void setBarcode(String barcode)            { this.barcode = barcode; }
    public void setBuyPrice(Integer buyPrice)         { this.buyPrice = buyPrice; }
    public void setReorderLevel(Integer reorderLevel) { this.reorderLevel = reorderLevel; }
    public void setUnit(String unit)                  { this.unit = unit; }
    public void setStockQty(Integer stockQty)         { this.stockQty = stockQty; }
}