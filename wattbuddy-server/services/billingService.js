const pool = require('../db');

/**
 * BillingService - Comprehensive billing calculation system
 * Implements 4 core billing formulas:
 * 1. Power: P = V × I × PF (watts)
 * 2. Energy: E = (P × seconds) / 3600000 (kWh)
 * 3. Bill: Bill = BaseCharge + (KWh × Rate) (rupees)
 * 4. Prediction: (CurrentKwh / DaysPassed) × 30 × Rate + BaseCharge
 */

class BillingService {
  /**
   * FORMULA 1: Calculate power consumption
   * P = V × I × PF (Watts)
   * @param {number} voltage - RMS voltage in volts
   * @param {number} current - RMS current in amperes
   * @param {number} powerFactor - Power factor (default 0.95 for India AC)
   * @returns {number} Power in watts
   * Example: 230V × 2A × 0.95 = 437W
   */
  static calculatePower(voltage, current, powerFactor = 0.95) {
    return voltage * current * powerFactor;
  }

  /**
   * FORMULA 2: Convert power to energy consumption
   * E = (P × seconds) / 3600000 (kWh)
   * @param {number} powerWatts - Power in watts
   * @param {number} timeSeconds - Time duration in seconds (default 1)
   * @returns {number} Energy in kWh
   * Example: (414W × 3600s) / 3600000 = 0.414 kWh per hour
   */
  static convertPowerToEnergy(powerWatts, timeSeconds = 1) {
    return (powerWatts * timeSeconds) / 3600000;
  }

  /**
   * FORMULA 3: Calculate billing amount
   * Bill = BaseCharge + (KWh × RatePerKwh) (Rupees)
   * @param {number} totalKwh - Total energy consumed in kWh
   * @param {number} baseCharge - Fixed base charge in rupees (default ₹50)
   * @param {number} ratePerKwh - Rate per kWh in rupees (default ₹10)
   * @returns {object} Bill breakdown with total, fixed, and variable components
   * Example: 50 + (120 × 10) = ₹1250
   */
  static calculateBill(totalKwh, baseCharge = 50, ratePerKwh = 10) {
    const variableCharge = totalKwh * ratePerKwh;
    const totalBill = baseCharge + variableCharge;

    return {
      baseCharge: baseCharge,
      energy_kwh: totalKwh,
      rate_per_kwh: ratePerKwh,
      variable_charge: variableCharge,
      total_bill: totalBill
    };
  }

  /**
   * FORMULA 4: Predict monthly bill based on current usage
   * PredictedBill = (CurrentKwh / DaysPassed) × 30 × Rate + BaseCharge
   * @param {number} currentKwh - Total kWh consumed so far this month
   * @param {number} daysPassed - Number of days elapsed in current month
   * @param {number} ratePerKwh - Rate per kWh in rupees (default ₹10)
   * @param {number} baseCharge - Fixed base charge in rupees (default ₹50)
   * @returns {object} Prediction with projected bill and confidence level
   * Example: (40 / 10) × 30 × 10 + 50 = ₹1250 (40% confidence with 10 days)
   */
  static predictMonthlyBill(currentKwh, daysPassed, ratePerKwh = 10, baseCharge = 50) {
    if (daysPassed <= 0) {
      return {
        projected_kwh: 0,
        projected_bill: baseCharge,
        confidence_percent: 0,
        message: 'No data available for prediction'
      };
    }

    // Daily average consumption
    const dailyAverageKwh = currentKwh / daysPassed;

    // Project to full 30-day month
    const projectedMonthlyKwh = dailyAverageKwh * 30;

    // Calculate projected bill
    const projectedBill = baseCharge + (projectedMonthlyKwh * ratePerKwh);

    // Confidence increases with more days of data (0% at 0 days, 100% at 30 days)
    const confidencePercent = Math.min((daysPassed / 30) * 100, 100);

    return {
      current_kwh: currentKwh,
      days_passed: daysPassed,
      daily_average_kwh: parseFloat(dailyAverageKwh.toFixed(3)),
      projected_kwh: parseFloat(projectedMonthlyKwh.toFixed(2)),
      projected_bill: parseFloat(projectedBill.toFixed(2)),
      base_charge: baseCharge,
      rate_per_kwh: ratePerKwh,
      confidence_percent: parseFloat(confidencePercent.toFixed(1))
    };
  }

  /**
   * Get current month's energy consumption for a user
   * Uses monthly snapshot method (current_total - snapshot_at_month_start)
   * This is more accurate and handles ESP32 resets gracefully
   * @param {number} userId - User ID
   * @returns {Promise<number>} Total kWh consumed this month
   */
  static async getCurrentMonthUsage(userId) {
    try {
      const MonthlySnapshotService = require('./monthlySnapshotService');
      return await MonthlySnapshotService.getCurrentMonthUsage(userId);
    } catch (error) {
      console.error('Error fetching current month usage:', error);
      // Fallback to old method if snapshot fails
      try {
        const currentMonth = new Date().getMonth() + 1;
        const currentYear = new Date().getFullYear();

        const query = `
          SELECT COALESCE(MAX(energy_consumed) - MIN(energy_consumed), 0) AS total_units_kwh
          FROM "EnergyReadings"
          WHERE user_id = $1::text
          AND EXTRACT(MONTH FROM timestamp) = $2
          AND EXTRACT(YEAR FROM timestamp) = $3
        `;

        const result = await pool.query(query, [userId.toString(), currentMonth, currentYear]);
        return parseFloat(result.rows[0]?.total_units_kwh || 0);
      } catch (fallbackError) {
        console.error('Fallback method also failed:', fallbackError);
        throw error;
      }
    }
  }

  /**
   * Get number of days elapsed in current month (1-31)
   * @returns {number} Current day of month
   */
  static getDaysElapsed() {
    return new Date().getDate();
  }

  /**
   * Calculate complete bill for current month with all details
   * @param {number} userId - User ID
   * @param {number} baseCharge - Fixed monthly charge (default ₹50)
   * @param {number} ratePerKwh - Rate per unit consumption (default ₹10)
   * @returns {Promise<object>} Complete billing details
   */
  static async calculateCurrentBill(userId, baseCharge = 50, ratePerKwh = 10) {
    try {
      const kwh = await this.getCurrentMonthUsage(userId);
      const billBreakdown = this.calculateBill(kwh, baseCharge, ratePerKwh);

      return {
        user_id: userId,
        billing_period: new Date().toLocaleDateString('en-IN', { month: 'long', year: 'numeric' }),
        ...billBreakdown
      };
    } catch (error) {
      console.error('Error calculating current bill:', error);
      throw error;
    }
  }

  /**
   * Get historical bills for past months
   * @param {number} userId - User ID
   * @param {number} monthsBack - Number of past months to retrieve (default 6)
   * @param {number} baseCharge - Fixed monthly charge (default ₹50)
   * @param {number} ratePerKwh - Rate per unit consumption (default ₹10)
   * @returns {Promise<array>} Array of historical bills
   */
  static async getHistoricalBills(userId, monthsBack = 6, baseCharge = 50, ratePerKwh = 10) {
    try {
      const bills = [];
      const today = new Date();

      for (let i = 0; i < monthsBack; i++) {
        const monthDate = new Date(today.getFullYear(), today.getMonth() - i, 1);
        const month = monthDate.getMonth() + 1;
        const year = monthDate.getFullYear();

        const query = `
          SELECT COALESCE(MAX(energy_consumed) - MIN(energy_consumed), 0) AS total_units_kwh
          FROM "EnergyReadings"
          WHERE user_id = $1::text
          AND EXTRACT(MONTH FROM timestamp) = $2
          AND EXTRACT(YEAR FROM timestamp) = $3
        `;

        const result = await pool.query(query, [userId.toString(), month, year]);
        const kwh = parseFloat(result.rows[0]?.total_units_kwh || 0);
        const billBreakdown = this.calculateBill(kwh, baseCharge, ratePerKwh);

        const monthName = monthDate.toLocaleDateString('en-IN', { month: 'long', year: 'numeric' });

        bills.push({
          period: monthName,
          ...billBreakdown
        });
      }

      return bills.reverse(); // Oldest first
    } catch (error) {
      console.error('Error fetching historical bills:', error);
      throw error;
    }
  }

  /**
   * Get comprehensive billing summary with current and projected bills
   * @param {number} userId - User ID
   * @param {number} baseCharge - Fixed monthly charge (default ₹50)
   * @param {number} ratePerKwh - Rate per unit consumption (default ₹10)
   * @returns {Promise<object>} Complete summary with current, projection, and comparison
   */
  static async getBillingSummary(userId, baseCharge = 50, ratePerKwh = 10) {
    try {
      // Current month data
      const currentKwh = await this.getCurrentMonthUsage(userId);
      const daysElapsed = this.getDaysElapsed();
      const currentBill = this.calculateBill(currentKwh, baseCharge, ratePerKwh);
      const projection = this.predictMonthlyBill(currentKwh, daysElapsed, ratePerKwh, baseCharge);

      // Get last month data for comparison (simplified: assume similar usage)
      const lastMonthData = new Date();
      lastMonthData.setMonth(lastMonthData.getMonth() - 1);
      const lastMonth = lastMonthData.getMonth() + 1;
      const lastYear = lastMonthData.getFullYear();

      const lastMonthQuery = `
        SELECT COALESCE(MAX(energy_consumed) - MIN(energy_consumed), 0) AS total_units_kwh
        FROM "EnergyReadings"
        WHERE user_id = $1::text
        AND EXTRACT(MONTH FROM timestamp) = $2
        AND EXTRACT(YEAR FROM timestamp) = $3
      `;

      const lastMonthResult = await pool.query(lastMonthQuery, [userId.toString(), lastMonth, lastYear]);
      const lastMonthKwh = parseFloat(lastMonthResult.rows[0]?.total_units_kwh || 0);
      const lastMonthBill = this.calculateBill(lastMonthKwh, baseCharge, ratePerKwh);

      const monthChangePercent = lastMonthKwh > 0
        ? (((currentKwh - lastMonthKwh) / lastMonthKwh) * 100).toFixed(1)
        : 0;

      return {
        user_id: userId,
        current_month: {
          period: new Date().toLocaleDateString('en-IN', { month: 'long', year: 'numeric' }),
          days_elapsed: daysElapsed,
          energy_kwh: currentKwh,
          bill_amount: currentBill.total_bill
        },
        projection: projection,
        last_month: {
          period: lastMonthData.toLocaleDateString('en-IN', { month: 'long', year: 'numeric' }),
          energy_kwh: lastMonthKwh,
          bill_amount: lastMonthBill.total_bill
        },
        comparison: {
          kwh_change: parseFloat((currentKwh - lastMonthKwh).toFixed(2)),
          kwh_change_percent: parseFloat(monthChangePercent),
          bill_change: parseFloat((currentBill.total_bill - lastMonthBill.total_bill).toFixed(2))
        }
      };
    } catch (error) {
      console.error('Error generating billing summary:', error);
      throw error;
    }
  }
}

module.exports = BillingService;
